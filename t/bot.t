# TODO: write more tests

use Test;
BEGIN { plan tests => 16 };
use Bot::CPAN;
ok(1);

my $bot = Bot::CPAN->new();
ok(ref $bot, 'Bot::CPAN');
ok($bot->get('news_server')  eq 'nntp.perl.org');
ok($bot->get('group') eq 'perl.cpan.testers');
ok($bot->get('reload_indices_interval') == 300);
ok($bot->get('inform_channel_of_new_uploads') == 60);
ok($bot->get('search_max_results') == 20);
ok($bot->debug == 0);
ok($bot->server eq 'london.rhizomatic.net');
ok($bot->port == 6667);
ok($bot->nick);
ok(scalar @{$bot->alt_nicks} == 0);
ok($bot->username eq $bot->nick);
ok($bot->username . ' bot' eq $bot->name);
ok(scalar @{$bot->ignore_list} == 0);
ok(scalar keys %{$bot->get('policy')} == 0);
