package DBIx::SchemaUpgrader;
# ABSTRACT: Automatically upgrade a database schema

use strict;
use warnings;

=method new

Constructor;  Accepts a hash or hashref of options.
Current option:

=for :list
* C<dbh> - A B<d>ataB<b>ase B<h>andle (as returned from C<< DBI->connect >>)

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
	return $#{ $self->instructions };
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
	$self->instructions->[$version]->($self);

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
	my $dbh = Local::Database->new()->dbh;

	# do something with $dbh which now contains the schema you expect

=head1 DESCRIPTION

B<NOTE>: This API is under construction and subject to change.

=head1 TODO

=for :list
* Rename this module
* use L<DBI/quote_identifier> on the table name

=head1 SEE ALSO

=for :list
* L<DBIx::VersionedSchema>
* L<DBIx::VersionedDDL>
* L<ORLite::Migrate> (L<http://use.perl.org/~Alias/journal/38087>)

=cut
