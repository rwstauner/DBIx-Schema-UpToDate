# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
use strict;
use warnings;

package DBIx::Schema::UpToDate;
# ABSTRACT: Helps keep a database schema up to date

use Carp qw(croak carp); # core

=method new

Constructor;  Accepts a hash or hashref of options.

Options used by the base module:

=for :list
* C<dbh> - A B<d>ataB<b>ase B<h>andle (as returned from C<< DBI->connect >>)
Database commands will be executed against this handle.
* C<auto_update> - Boolean
By default L</up_to_date> is called at initialization
(just after being blessed).
Set this value to false to disable this if you need to do something else
before updating.  You will have to call L</up_to_date> yourself.
* C<transactions> - Boolean
By default L</update_to_version> does its work in a transaction.
Set this value to false to disable this behavior
(in case your database doesn't support transactions).

=cut

sub new {
  my $class = shift;
  my $self = {
    auto_update => 1,
    transactions => 1,
    @_ == 1 ? %{$_[0]} : @_
  };
  bless $self, $class;

  # make sure the database schema is current
  $self->up_to_date()
    if $self->{auto_update};

  return $self;
}

=method begin_work

Convenience method for calling L<DBI/begin_work>
on the database handle if C<transactions> are enabled.

=method commit

Convenience method for calling L<DBI/commit>
on the database handle if C<transactions> are enabled.

=cut

foreach my $action ( qw(begin_work commit) ){
  no strict 'refs'; ## no critic (NoStrict)
  *$action = sub {
    my ($self) = @_;
    if( $self->{transactions} ){
      my $dbh = $self->dbh;
      $dbh->$action()
        or croak $dbh->errstr;
    }
  }
}


=method dbh

Returns the object's database handle.

=cut

sub dbh {
  my ($self) = @_;
  return $self->{dbh};
}

=method current_version

Determine the current version of the database schema.

=cut

sub current_version {
  my ($self) = @_;
  my $dbh = $self->dbh;
  my $table = $self->version_table_name;
  my $version;

  my $tables = $dbh->table_info('%', '%', $table, 'TABLE')
    ->fetchall_arrayref;

  # if table exists query it for current database version
  if( @$tables ){
    my $qtable = $self->quoted_table_name;
    my $field = $dbh->quote_identifier('version');

    my $v = $dbh->selectcol_arrayref(
      "SELECT $field from $qtable ORDER BY $field DESC LIMIT 1"
    )->[0];
    $version = $v
      if defined $v;
  }

  return $version;
}

=method initialize_version_table

Create the version metadata table in the database and
insert initial version record.

=cut

sub initialize_version_table {
  my ($self) = @_;
  my $dbh = $self->dbh;

  my ($version, $updated) = $self->quote_identifiers(qw(version updated));

  $self->begin_work();

  $dbh->do('CREATE TABLE ' . $self->quoted_table_name .
    " ($version integer, $updated timestamp)"
  )
    or croak $dbh->errstr;

  $self->set_version(0);

  $self->commit();
}

=method latest_version

Returns the latest [possible] version of the database schema.

=cut

sub latest_version {
  my ($self) = @_;
  return scalar @{ $self->updates };
}

=method quoted_table_name

Returns the table name (L</version_table_name>)
quoted by L<DBI/quote_identifier>.

=cut

sub quoted_table_name {
  my ($self) = @_;
  return $self->dbh->quote_identifier($self->version_table_name);
}

=method quote_identifiers

  @quoted = $self->quote_identifiers(qw(field1 field2));

Convenience method for passing each argument
through L<DBI/quote_identifier>.

Returns a list.

=cut

sub quote_identifiers {
  my ($self, @names) = @_;
  my $dbh = $self->dbh;
  return map { $dbh->quote_identifier($_) } @names;
}

=method set_version

  $cache->set_version($verison);

Sets the current database version to C<$version>.
Called from L</update_to_version> after executing the appropriate update.

=cut

sub set_version {
  my ($self, $version) = @_;
  my $dbh = $self->dbh;

  $dbh->do('INSERT INTO ' . $self->quoted_table_name .
    ' (' .
      join(', ', $self->quote_identifiers(qw(version updated)))
    . ') VALUES(?, ?)',
    {}, $version, time()
  )
    or croak $dbh->errstr;
}

=method updates

Returns an arrayref of subs (coderefs)
that can be used to update the database from one version to the next.
This is used by L</up_to_date> to replay a recorded database history
on the L</dbh> until the database schema is up to date.

=cut

sub updates {
  my ($self) = @_;
  return $self->{updates} ||= [
  ];
}

=method update_to_version

  $cache->update_to_version($version);

Executes the update associated with C<$version>
in order to bring database up to that version.

=cut

sub update_to_version {
  my ($self, $version) = @_;

  $self->begin_work();

  # execute updates to bring database to $version
  $self->updates->[$version - 1]->($self);

  # save the version now in case we get interrupted before the next commit
  $self->set_version($version);

  $self->commit();
}

=method up_to_date

Ensures that the database is up to date.
If it is not it will apply updates
after L</current_version> up to L</latest_version>
to bring the schema up to date.

=cut

sub up_to_date {
  my ($self) = @_;

  my $current = $self->current_version;
  if( !defined($current) ){
    $self->initialize_version_table;
    $current = $self->current_version;
    die("Unable to initialize version table\n")
      if !defined($current);
  }

  my $latest = $self->latest_version;

  # execute each update required to go from current to latest version
  # (starting with next version, obviously (don't redo current))
  $self->update_to_version($_)
    foreach ($current + 1) .. $latest;
}

=method version_table_name

The name to use the for the schema version metadata.

Defaults to C<'schema_version'>.

=cut

sub version_table_name {
  'schema_version'
}

1;

=for :stopwords TODO dbh

=for test_synopsis
my @connection_args;

=head1 SYNOPSIS

  package Local::Database;
  use parent 'DBIx::Schema::UpToDate';

  sub updates {
    shift->{updates} ||= [

      # version 1
      sub {
        my ($self) = @_;
        $self->dbh->do('-- sql');
        $self->do_something_else;
      },

      # version 2
      sub {
        my ($self) = @_;
        my $val = Local::Project::NewerClass->value;
        $self->dbh->do('INSERT INTO values (?)', {}, $val);
      },
    ];
  }

  package main;

  my $dbh = DBI->connect(@connection_args);
  Local::Database->new(dbh => $dbh);

  # do something with $dbh which now contains the schema you expect

=head1 DESCRIPTION

This module provides a base class for keeping a database schema up to date.
If you need to make changes to the schema
in remote databases in an automated manner
you may not be able to ensure what version of the database is installed
by the time it gets the update.
This module will apply updates (defined as perl subs (coderefs))
sequentially to bring the database schema
up to the latest version from whatever the current version is.

The aim of this module is to enable you to write incredibly simple subclasses
so that all you have to do is define the updates you want to apply.
This is done with subs (coderefs) so you can access the object
and its database handle.

It is intentionally simple and is not intended for large scale applications.
It may be a good fit for small embedded databases.
It can also be useful if you need to reference other parts of your application
as the subs allow you to utilize the object (and anything else you can reach).

Check L</SEE ALSO> for alternative solutions
and pick the one that's right for your situation.

=head1 USAGE

Subclasses should overwrite L</updates>
to return an arrayref of subs (coderefs) that will be executed
to bring the schema up to date.

Each sub (coderef) will be called as a method
(it will receive the object as its first parameter):

  sub { my ($self) = @_; $self->dbh->do('...'); }

The rest of the methods are small in the hopes that you
can overwrite the ones you need to get the customization you require.

The updates can be run individually (outside of L</up_to_date>)
for testing your subs...

  my $dbh = DBI->connect(@in_memory_database);
  my $schema = DBIx::Schema::UpToDate->new(dbh => $dbh, auto_update => 0);

  # don't forget this:
  $schema->initialize_version_table;

  $schema->update_to_version(1);
  # execute calls on $dbh to test changes
  $schema->dbh->do( @something );
  # test row output or column information or whatever
  ok( $test_something, $here );

  $schema->update_to_version(2);
  # test things

  $schema->update_to_version(3);
  # test changes

  ...

  is($schema->current_version, $schema->latest_version, 'updated to latest version');
  done_testing;

=head1 TODO

=for :list
* Come up with a better name (too late).
* Add an initial_version attribute to allow altering the history
* Confirm that the driver handles LIMIT 1 before trying to use it.

=head1 RATIONALE

I had already written most of the logic for this module in another project
when I realized I should abstract it.
Then I went looking and found the modules listed in L</SEE ALSO>
but didn't find one that fit my needs, so I released what I had made.

=head1 SEE ALSO

Here are a number of alternative modules I have found
(some older, some newer) that perform a similar task,
why I didn't use them,
and why you probably should.

=for :list
* L<DBIx::VersionedSchema>
Was close to what I was looking for, but not customizable enough.
Were I to subclass it I would have needed to overwrite the two main methods.
* L<DBIx::VersionedDDL>
Much bigger scale than what I was looking for.
Needed something without L<Moose>.
* L<DBIx::Migration::Classes>
Something new(er than this module)... haven't investigated.
* L<ORLite::Migrate> (L<http://use.perl.org/~Alias/journal/38087>)
Much bigger scale than what I was looking for.
Wasn't using L<ORLite>, and didn't want to use separate script files.
* L<DBIx::Class::Schema::Versioned>
Not using L<DBIx::Class>; again, significantly larger scale than I desired.
* L<DBIx::Class::DeploymentHandler>
Not using L<DBIx::Class>; more powerful than the previous means
it's even larger than what was already more than I needed.

=cut
