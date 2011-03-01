package DBIx::SchemaUpgrader;
# ABSTRACT: Automatically upgrade a database schema

use strict;
use warnings;

=method new

Constructor;  Accepts a hash or hashref of options.

Options used by the base module:

=for :list
* C<dbh> - A B<d>ataB<b>ase B<h>andle (as returned from C<< DBI->connect >>)
Database commands will be executed against this handle.
* C<build> - Boolean
By default L</build> is called at initialization (after being blessed).
Set this value to false to disable this if you need to do something else
before building.  You will have to call L</build> yourself.

=cut

sub new {
	my $class = shift;
	my $self = {
		build => 1,
		@_ == 1 ? %{$_[0]} : @_
	};
	bless $self, $class;

	# make sure the database schema is current
	$self->build()
		if $self->{build};

	return $self;
}

=item dbh

Returns the object's database handle.

=cut

sub dbh {
	my ($self) = @_;
	return $self->{dbh};
}

=item build

Builds the database from L</current_version> to L</latest_version>
performing whatever tasks may be necessary to bring the schema up to date.

=cut

sub build {
	my ($self) = @_;
	my $dbh = $self->dbh;

	my $current = $self->current_version;
	if( !defined($current) ){
		$self->initialize_version_table;
		$current = $self->current_version;
		die("Unable to initialize version table\n")
			if !defined($current);
	}

	my $latest = $self->latest_version;

	# execute each instruction required to go from current to latest version
	# (starting with next version, obviously (don't redo current))
	$self->update_to_version($_)
		foreach ($current + 1) .. $latest;
}

=item current_version

Determine the current version of the database schema.

=cut

sub current_version {
	my ($self) = @_;
	my $dbh = $self->dbh;
	my $table = $self->version_table_name;
	my $version;

	my $tables = $dbh->table_info('%', '%', $table, 'TABLE')
		->fetchall_arrayref;

	# get current database version
	if( @$tables ){
		my $v = $dbh->selectcol_arrayref(
			"SELECT version from $table ORDER BY version DESC LIMIT 1"
		)->[0];
		$version = $v
			if defined $v;
	}

	return $version;
}

=item initialize_version_table

Create the version metadata table in the database and
insert initial version record.

=cut

sub initialize_version_table {
	my ($self) = @_;
	$self->dbh->do('CREATE TABLE ' . $self->version_table_name .
		' (version integer, upgraded timestamp)');
	$self->set_version(0);
}

=item instructions

Returns an arrayref of subs (coderefs)
that can be used to rebuild the database from one version to the next.
This is used by L</build> to replay a recorded database history
on the L</dbh> until the database schema is up to date.

=cut

sub instructions {
	my ($self) = @_;
	return $self->{instructions} ||= [
	];
}

=item latest_version

Returns the latest [possible] version of the database schema.

=cut

sub latest_version {
	my ($self) = @_;
	return scalar @{ $self->instructions };
}

=item set_version

	$cache->set_version($verison);

Sets the current database version to C<$version>.
Called from L</update_to_version> after executing the appropriate instruction.

=cut

sub set_version {
	my ($self, $version) = @_;
	$self->dbh->do('INSERT INTO ' . $self->version_table_name .
		' (version, upgraded) VALUES(?, ?)',
		{}, $version, time);
}

=item update_to_version

	$cache->update_to_version($version);

Executes the instruction associated with C<$version>
in order to bring database up to that version.

=cut

sub update_to_version {
	my ($self, $version) = @_;
	my $dbh = $self->dbh;

	$dbh->begin_work();

	# execute instructions to update database to $version
	$self->instructions->[$version - 1]->($self);

	# save the version now in case we get interrupted before the next commit
	$self->set_version($version);

	$dbh->commit();
}

=item version_table_name

The name to use the for the schema version metadata.

Defaults to C<'schema_version'>.

=cut

sub version_table_name {
	'schema_version'
}

1;

=head1 SYNOPSIS

	package Local::Database;
	use parent 'DBIx::SchemaUpgrader';

	sub instructions {
		my ($self) = @_;
		my $dbh = $self->dbh;
		$self->{instructions} ||= [
			sub {
				$dbh->do('-- sql');
				$self->do_something_else;
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
This module will apply patches sequentially to bring the database schema
up to the latest version from whatever the current version is.

The aim of this module is to enable you to write incredibly simple subclasses
so that all you have to do is define the updates you want to apply.
This is done with subs (coderefs) so you can access the object
and its database handle.

It is intentially simple and is not intended for large scale applications.
Check L</SEE ALSO> for alternative solutions
and pick the one that's right for your situation.

=head1 USAGE

Subclasses should overwrite L</instructions>
to return an arrayref of subs (coderefs) that will be executed
to bring the schema up to date.

The rest of the methods are small in the hopes that you
can overwrite the ones you need to get the customization you require.

=head1 TODO

=for :list
* Rename this module
* Use L<DBI/quote_identifier> on the table name

=head1 RATIONALE

I had already written most of the logic for this module in another project
when I realized I should abstract it.
Then I went looking and found the modules listed in L</SEE ALSO>
but didn't find one that fit my needs, so I released what I had made.

=head1 SEE ALSO

=for :list
* L<DBIx::VersionedSchema>
Was close to what I was looking for, but not customizable enough.
Were I to subclass it I would have needed to overwrite the two main methods.
* L<DBIx::VersionedDDL>
Much bigger scale than what I was looking for.
Needed something without Moose.
* L<ORLite::Migrate> (L<http://use.perl.org/~Alias/journal/38087>)
Much bigger scale than what I was looking for.
Wasn't using ORLite, and didn't want to use separate script files

=cut
