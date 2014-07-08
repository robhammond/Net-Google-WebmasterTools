Net-Google-WebmasterTools
=========================

A (very) basic Perl port of https://github.com/eyecatchup/php-webmaster-tools-downloads/ because.. ugh PHP.

Can be used as follows to download daily top pages and query reports for a specified period:

`#!/usr/bin/env perl
use strict;
use Net::Google::WebmasterTools;
use Date::Calc::Iterator;

my $email = 'example@google.com';
my $pass = '12345';

my $i1 = Date::Calc::Iterator->new(from => ['2014','04','09'], to => ['2014','07','03']);

while (my @date = $i1->next) {
	my $date = $date[0] . "-" . sprintf("%02d", $date[1]) . "-" . sprintf("%02d", $date[2]);
	my $dates = [$date, $date];
	
	print "Getting $date\n";

	my $gwt = Net::Google::WebmasterTools->new();

	if ($gwt->LogIn($email, $pass)) {
		my $sites = $gwt->GetSites();
		for my $site (@$sites) {
			$gwt->SetDaterange($dates);
			$gwt->DownloadCSV($site);
		}
	}
	sleep(1);
}`
