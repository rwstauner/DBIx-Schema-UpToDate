use strict;
use warnings;
use Test::More 0.96;
use Test::MockObject 1.09;

my $mod = 'DBIx::Schema::UpToDate';
eval "require $mod" or die $@;

my ($table_info, $db_ver);
my $sth = Test::MockObject->new()
	->mock(fetchall_arrayref => sub { $table_info })
	->mock(fetchall_hashref  => sub { $table_info });

my @dbh_done;
my $dbh = Test::MockObject->new()
	->mock(begin_work => sub { 1 })
	->mock(commit     => sub { 1 })
	->mock(do => sub { push(@dbh_done, $_[1]) })
	->mock(selectcol_arrayref => sub { [$db_ver] })
	->mock(table_info => sub { $sth });

my $schema = new_ok($mod, [dbh => $dbh, build => 0]);

# current_version
$table_info = [];
is($schema->current_version, undef, 'not built');
$table_info = [version => {}];
$db_ver = 1;
is($schema->current_version, 1, 'version fetched');

# latest_version
$schema->{instructions} = [1, 2, 3, 4];
is($schema->latest_version, 4, 'fake latest_version');
delete $schema->{instructions};
# this one's a little silly
is($schema->latest_version, @{ $schema->instructions }, 'latest version');

# build
my $updated = 0;
$db_ver = 0;
$schema->{instructions} = [sub { $updated++ }, sub { $updated++ }];

$sth->set_series('fetchall_arrayref', [], [1]);
$schema->build;
is($updated, 2, 'correct number of updates');

$sth->mock('fetchall_arrayref', sub { [1] });

$updated = 0;
$db_ver = 1;
$schema->build;
is($updated, 1, 'correct number of updates');

$updated = 0;
$db_ver = 2;
$schema->build;
is($updated, 0, 'correct number of updates');

$sth->set_series('fetchall_arrayref', [], []);
is(eval { $schema->build; }, undef, 'build dies w/o current version');
like($@, qr/version table/, 'build died w/o version table');

# update_to_version
my $inst = [0, 0];
$schema->{instructions} = [sub { $inst->[0]++ }, sub { $inst->[1]++ }];
$schema->update_to_version(2);
is_deeply($inst, [0,1], 'correct instruction executed');
$schema->update_to_version(1);
is_deeply($inst, [1,1], 'correct instruction executed');
$schema->update_to_version(1);
is_deeply($inst, [2,1], 'correct instruction executed');

done_testing;
