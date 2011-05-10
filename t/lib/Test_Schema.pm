# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
package
  Test_Schema;

require DBIx::Schema::UpToDate;
our @ISA = qw(DBIx::Schema::UpToDate);

sub updates {
  shift->{updates} ||= [
    # v1
    sub {
      my ($self) = @_;
      $self->dbh->do(q[CREATE TABLE tbl1 (fld1 text, fld2 int)]);
      $self->dbh->do(q[INSERT INTO tbl1 VALUES('goo', 1)]);
    },
    # v2
    sub {
      my ($self) = @_;
      $self->dbh->do(q[INSERT INTO tbl1 VALUES('ber', 2)]);
    },
  ];
}
