# TODO: write some more tests

use Test;
BEGIN { plan tests => 6 };
use Bot::CPAN;
ok(1);

my $bot = Bot::CPAN->new();
ok(ref $bot, 'Bot::CPAN');
ok($bot->get('news_server')  eq 'nntp.perl.org');
ok($bot->get('group') eq 'perl.cpan.testers');
ok($bot->get('reload_indices_interval') == 300);
ok($bot->get('inform_channel_of_new_uploads') == 60);
