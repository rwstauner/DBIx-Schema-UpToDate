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
		@_ == 1 ? %{$_[0]} : @_
	};
	bless $self, $class;
	$self->build;
	$self;
}

=item dbh

Returns the object's database handle.

=cut

sub dbh {
	my ($self) = @_;
	return $self->{dbh};
}

=item build

Builds the database from its current version to the latest version
performing whatever tasks may be necessary to bring the schema up to date.

=cut

sub build {
	my ($self) = @_;
	my $dbh = $self->dbh;

	my $version = -1;
	my $tables = $dbh->table_info()->fetchall_hashref('table_name');

	if( exists($tables->{version}) ){
		$version = $dbh->selectcol_arrayref(
			'SELECT version from version'
		)->[0];
	}

	my $changes = $self->instructions();
	for(my $v = $version + 1; $v < @$changes; ++$v){
		$dbh->begin_work();
		# execute instructions to update database to version $v
		$changes->[$v]->($self);
		# save the version now in case we get interrupted before the next save
		$dbh->do('UPDATE version SET version = ?', {}, $v);
		$dbh->commit();
	}
}

=item instructions

Returns an arrayref of subs (coderefs)
that can be used to rebuild the database from one version to the next.
This is used by L</build> to replay a recorded database history
on the L</dbh> until the database schema is up to date.

=cut

sub instructions {
	my ($self) = @_;
	return [
		# v0: 2011-02-08: database version metadata
		sub {
			$self->dbh->do('CREATE TABLE version (version integer)');
			$self->dbh->do('INSERT INTO  version (version) VALUES(0)');
		},
	];
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

=head1 TODO

=for :list
* Rename this module

=head1 SEE ALSO

=for :list
* L<DBIx::VersionedSchema>
* L<DBIx::VersionedDDL>
* L<ORLite::Migrate> (L<http://use.perl.org/~Alias/journal/38087>)

=cut
