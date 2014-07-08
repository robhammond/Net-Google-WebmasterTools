package Net::Google::WebmasterTools;
use strict;
use warnings;

use DateTime;
use Data::Dumper;
use Mojo::UserAgent;
use Mojo::DOM;
use Mojo::Util qw(url_escape decode);
use Mojo::JSON;
use Mojo::Log;
use Mojo::Home;

# /**
#  *  Perl port of PHP class for downloading CSV files from Google Webmaster Tools.
#  *
#  *  This class does NOT require the Zend gdata package be installed
#  *  in order to run.
#  *
#  *  Copyright 2012 eyecatchUp UG. All Rights Reserved.
#  *
#  *  Licensed under the Apache License, Version 2.0 (the "License");
#  *  you may not use this file except in compliance with the License.
#  *  You may obtain a copy of the License at
#  *
#  *     http://www.apache.org/licenses/LICENSE-2.0
#  *
#  *  Unless required by applicable law or agreed to in writing, software
#  *  distributed under the License is distributed on an "AS IS" BASIS,
#  *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  *  See the License for the specific language governing permissions and
#  *  limitations under the License.
#  *
#  *  @author: Stephan Schmitz <eyecatchup@gmail.com>
#  *  @link:   https://code.google.com/p/php-webmaster-tools-downloads/
#  *  @link:   https://github.com/eyecatchup/php-webmaster-tools-downloads/
#  */

my $home = Mojo::Home->new;
$home->detect;
my $cur_dir = $home->rel_dir('./');


my $log = Mojo::Log->new;


sub new {
    my $class = shift;
    my $self = { @_ };

    $self->{'host'} = 'https://www.google.com';
	$self->{'service_uri'} = '/webmasters/tools/';

    $self->{'_auth'} = 0;
	$self->{'_logged_in'} = 0;
	$self->{'_language'} = "en";
	$self->{'_daterange'} = [];
	$self->{'_tables'} = [
		"TOP_PAGES", 
		"TOP_QUERIES",
		# "CRAWL_ERRORS", 
		# "CONTENT_ERRORS", 
		# "CONTENT_KEYWORDS",
		# "INTERNAL_LINKS",
		# "EXTERNAL_LINKS",
		# "SOCIAL_ACTIVITY",
  #       "LATEST_BACKLINKS"
			];
	$self->{'_errTablesSort'} = {
		0 => "http",
		1 => "not-found", 
		2 => "restricted-by-robotsTxt",
		3 => "unreachable", 
		4 => "timeout", 
		5 => "not-followed",
		"kAppErrorSoft-404s" => "soft404",
		"sitemap" => "in-sitemaps"
	};
	$self->{'_errTablesType'} = {
		0 => "web-crawl-errors",
		1 => "mobile-wml-xhtml-errors",
		2 => "mobile-chtml-errors",
		3 => "mobile-operator-errors",
		4 => "news-crawl-errors"
	};
	$self->{'_downloaded'} = [];
	$self->{'_skipped'} = [];

    bless ($self, $class);

    return $self;
}

# *  Sets content language.
# *  @param $str     String   Valid ISO 639-1 language code, supported by Google.

sub SetLanguage {
	my ($self, $str) = @_;
	$self->{'_language'} = $str;
}

# *  Sets features that should be downloaded.
# *
# *  @param $arr     Array   Valid array values are:
# *                          "TOP_PAGES", "TOP_QUERIES", "CRAWL_ERRORS", "CONTENT_ERRORS",
# *                          "CONTENT_KEYWORDS", "INTERNAL_LINKS", "EXTERNAL_LINKS",
# *                          "SOCIAL_ACTIVITY".

sub SetTables {
	my ($self, $arr) = @_;

	if(scalar @$arr <= 2) {

		my @valid = (
			"TOP_PAGES",
			"TOP_QUERIES",
			"CRAWL_ERRORS",
			"CONTENT_ERRORS",
		  	"CONTENT_KEYWORDS",
		  	"INTERNAL_LINKS",
		  	"EXTERNAL_LINKS",
		  	"SOCIAL_ACTIVITY",
          	"LATEST_BACKLINKS"
        );
		$self->{'_tables'} = [];

		for (my $i=0; $i < @$arr; $i++) {
			if (grep(/$arr->[$i]/, @valid)) {
				push $self->{'_tables'}, $arr->[$i];
			} else { 
				$log->error("Invalid argument given."); 
			}
		}
	} else { 
		$log->error("Invalid argument given."); 
	}
}

# *  Sets daterange for download data.
# *  @param $arr     Array   Array containing two ISO 8601 formatted date strings.

sub SetDaterange {
	my ($self, $arr) = @_;

	if (scalar @$arr == 2) {
		# if (self::IsISO8601($arr[0]) === true &&
		  # self::IsISO8601($arr[1]) === true) {
		my $date1 = $arr->[0];
		$date1 =~ s!-!!g;
		$log->info($date1);
		my $date2 = $arr->[1];
		$date2 =~ s!-!!g;
		$self->{'_daterange'} = [$date1, $date2];
		return 1;
		# } else { throw new Exception("Invalid argument given."); }
	} else { 
		$log->error("Invalid argument given."); 
	}
}

# Returns array of downloaded filenames.
# @return  Array   Array of filenames that have been written to disk.

sub GetDownloadedFiles {
	my $self = shift;
	return $self->{'_downloaded'};
}

# Returns array of downloaded filenames.
# *  @return  Array   Array of filenames that have been written to disk.

sub GetSkippedFiles {
	my $self = shift;
	return $self->{'_skipped'};
}

# Attempts to log into the specified Google account.
# 		 *  @param $email  String   User's Google email address.
# 		 *  @param $pwd    String   Password for Google account.
# 		 *  @return Boolean  Returns true when Authentication was successful,
# 		 *                   else false.

sub LogIn {
	my ($self, $email, $pwd) = @_;

	my $url = $self->{'host'} . '/accounts/ClientLogin';

	my $postRequest = {
		'accountType' => 'HOSTED_OR_GOOGLE',
		'Email' => $email,
		'Passwd' => $pwd,
		'service' => "sitemaps",
		'source' => "Google-WMTdownloadscript-0.1-pl"
	};

	my $ua = Mojo::UserAgent->new;

	my $tx = $ua->post($url => {} => form => $postRequest );

	if (my $res = $tx->success) {
		my ($auth) = $res->body =~ m{Auth=(.*)};
		if ($auth =~ m{.+}) {
			$self->{'_auth'} = $auth;
			$self->{'_logged_in'} = 1;
			return 1;
		} else {
			return;
		}
	} else {
		return;
	}
}

# Attempts authenticated GET Request.
# *  @param $url    String   URL for the GET request.
# *  @return Mixed  Curl result as String,
# *                 or false (Boolean) when Authentication fails.

sub GetData {
	my ($self, $url) = @_;

	if ($self->{'_logged_in'} == 1) {
		$url = $self->{'host'} . $url;
		my $headers = {
			Authorization => "GoogleLogin auth=" . $self->{'_auth'},
			"GData-Version" => 2
		};

		# $log->info(Dumper($headers));

		my $ua = Mojo::UserAgent->new;

		my $tx = $ua->get($url => $headers );

		if (my $res = $tx->success) {
			# $log->info(Dumper($tx->req));
			return $res->body;
		} else {
			$log->info(Dumper($tx->error));
			$log->info(Dumper($tx->req));
			$log->error("Unsuccessful request");
			die;
			return;
		}
	} else { 
		$log->error("Not logged in");
		return;
	}
}

# Gets all available sites from Google Webmaster Tools account.
# *  @return Mixed  Array with all site URLs registered in GWT account,
# *                 or false (Boolean) if request failed.

sub GetSites {
	my $self = shift;

	if ($self->{'_logged_in'} == 1) {
		my $feed = $self->GetData($self->{'service_uri'} . "feeds/sites/");

		if ($feed) {
			my @sites;
			my $doc = Mojo::DOM->new($feed);
			
			for my $node ($doc->find('entry')->each) {
				push @sites, $node->at('title')->all_text;
			}
			return \@sites;
		} else { 
			return;
		}
	} else { 
		return; 
	}
}

# *  Gets the download links for an available site
# *  from the Google Webmaster Tools account.
# *
# *  @param $url    String   Site URL registered in GWT.
# *  @return Mixed  Array with keys TOP_PAGES and TOP_QUERIES,
# *                 or false (Boolean) when Authentication fails.

sub GetDownloadUrls {
	my ($self, $url) = @_;
	if ($self->{'_logged_in'} == 1) {
		my $_url = sprintf($self->{'service_uri'} . "downloads-list?hl=%s&siteUrl=%s", $self->{'_language'}, url_escape $url);
		my $downloadList = $self->GetData($_url);

		my $json = Mojo::JSON->new;

		return $json->decode($downloadList);
	} else { 
		return; 
	}
}

# Downloads the file based on the given URL.
# *  @param $site    String   Site URL available in GWT Account.
# *  @param $savepath  String   Optional path to save CSV to (no trailing slash!).

sub DownloadCSV {
	my ($self, $site, $savepath) = @_;

	if (!$savepath) {
		$savepath = $cur_dir;
	}

	if ($self->{'_logged_in'} == 1) {
		my $downloadUrls = $self->GetDownloadUrls($site);

		my $fn = $site;
		$fn =~ s!https?://!!;
		$fn =~ s!/!!g;

		my $filename = "$fn-" . $self->{'_daterange'}->[0] . "-" . $self->{'_daterange'}->[1] . "--" . DateTime->now( time_zone => 'Europe/London' )->ymd . "-" . DateTime->now( time_zone => 'Europe/London' )->hms('');
		my $tables = $self->{'_tables'};

		for my $table (@$tables) {

			if ($table eq "CRAWL_ERRORS") {
				$self->DownloadCSV_CrawlErrors($site, $savepath);
			}
			elsif ($table eq "CONTENT_ERRORS") {
				$self->DownloadCSV_XTRA($site, $savepath,
				  "html-suggestions", "\)", "CONTENT_ERRORS", "content-problems-type-dl");
			}
			elsif ($table eq "CONTENT_KEYWORDS") {
				$self->DownloadCSV_XTRA($site, $savepath,
				  "keywords", "\)", "CONTENT_KEYWORDS", "content-words-dl");
			}
			elsif ($table eq "INTERNAL_LINKS") {
				$self->DownloadCSV_XTRA($site, $savepath,
				  "internal-links", "\)", "INTERNAL_LINKS", "internal-links-dl");
			}
			elsif ($table eq "EXTERNAL_LINKS") {
				$self->DownloadCSV_XTRA($site, $savepath,
				  "external-links-domain", "\)", "EXTERNAL_LINKS", "external-links-domain-dl");
			}
			elsif ($table eq "SOCIAL_ACTIVITY") {
				$self->DownloadCSV_XTRA($site, $savepath,
				  "social-activity", "x26", "SOCIAL_ACTIVITY", "social-activity-dl");
			}
            elsif ($table eq "LATEST_BACKLINKS") {
                $self->DownloadCSV_XTRA($site, $savepath,
				  "external-links-domain", "\)", "LATEST_BACKLINKS", "backlinks-latest-dl");
            }
			else {
				my $finalName = "$savepath/$table-$filename.csv";
				my $finalUrl = $downloadUrls->{$table} ."&prop=ALL&db=%s&de=%s&more=true";
				$finalUrl = sprintf($finalUrl, $self->{'_daterange'}->[0], $self->{'_daterange'}->[1]);
				$self->SaveData($finalUrl, $finalName);
			}
		}
	} else { 
		return; 
	}
}

# Downloads "unofficial" downloads based on the given URL.
# *  @param $site    String   Site URL available in GWT Account.
# *  @param $savepath  String   Optional path to save CSV to (no trailing slash!).

sub DownloadCSV_XTRA {
	my ($self, $site, $savepath, $tokenUri, $tokenDelimiter, $filenamePrefix, $dlUri) = @_;
	
	if (!$savepath) {
		die "no save path";
	}
	
	if ($self->{'_logged_in'} == 1) {
		my $uri = $self->{'service_uri'} . $tokenUri . "?hl=%s&siteUrl=%s";
		my $_uri = sprintf($uri, $self->{'_language'}, $site);

		my $token = $self->GetToken($_uri, $tokenDelimiter, $dlUri);

		my $fn = $site;
		$fn =~ s!https?://!!;
		$fn =~ s!/!!g;

		my $filename = "$fn-" . $self->{'_daterange'}->[0] . "-" . $self->{'_daterange'}->[1] . "--" . DateTime->now( time_zone => 'Europe/London' )->ymd . "-" . DateTime->now( time_zone => 'Europe/London' )->hms('');
		my $finalName = "$savepath/$filenamePrefix-$filename.csv";
		
		my $url = $self->{'service_uri'} . $dlUri . "?hl=%s&siteUrl=%s&security_token=%s&prop=ALL&db=%s&de=%s&more=true";
		my $_url = sprintf($url, $self->{'_language'}, $site, url_escape $token, $self->{'_daterange'}->[0], $self->{'_daterange'}->[1]);
		$self->SaveData($_url, $finalName);
	} else { 
		return; 
	}
}

# *  Downloads the Crawl Errors file based on the given URL.
# *
# *  @param $site    String   Site URL available in GWT Account.
# *  @param $savepath  String   Optional: Path to save CSV to (no trailing slash!).
# *  @param $separated Boolean  Optional: If true, the method saves separated CSV files
# *                             for each error type. Default: Merge errors in one file.

sub DownloadCSV_CrawlErrors {
	my ($self, $site, $savepath, $separated) = @_;

	if (!$savepath) {
		die 'no save path';
	}

	if ($self->{'_logged_in'} == 1) {
		my $type_param = "we";
		my $fn = $site;
		$fn =~ s!https?://!!;
		$fn =~ s!/!!g;
		my $filename = "$fn-" . $self->{'_daterange'}->[0] . "-" . $self->{'_daterange'}->[1] . "--" . DateTime->now( time_zone => 'Europe/London' )->ymd . "-" . DateTime->now( time_zone => 'Europe/London' )->hms('');

		# if ($separated) {
		# 	foreach($this->_errTablesSort as $sortid => $sortname) {
		# 		foreach($this->_errTablesType as $typeid => $typename) {
		# 			if($typeid == 1) {
		# 				$type_param = "mx";
		# 			} else if($typeid == 2) {
		# 				$type_param = "mc";
		# 			} else {
		# 				$type_param = "we";
		# 			}
		# 			$uri = self::SERVICEURI."crawl-errors?hl=en&siteUrl=$site&tid=$type_param";
		# 			$token = self::GetToken($uri,"x26");
		# 			$finalName = "$savepath/CRAWL_ERRORS-$typename-$sortname-$filename.csv";
		# 			$url = self::SERVICEURI."crawl-errors-dl?hl=%s&siteUrl=%s&security_token=%s&type=%s&sort=%s";
		# 			$_url = sprintf($url, $this->_language, $site, $token, $typeid, $sortid);
		# 			self::SaveData($_url,$finalName);
		# 		}
		# 	}
		# }
		# else {
			my $uri = $self->{'service_uri'} . "crawl-errors?hl=en&siteUrl=$site&tid=$type_param";
			my $token = $self->GetToken($uri, "x26");
			my $finalName = "$savepath/CRAWL_ERRORS-$filename.csv";
			my $url = $self->{'service_uri'} . "crawl-errors-new-dl?hl=%s&siteUrl=%s&security_token=%s&format=csv";
			my $_url = sprintf(url_escape $url, $self->{'_language'}, $site, url_escape $token);
			$self->SaveData($_url, $finalName);
		# }
	} else { 
		return; 
	}
}

#  *  Saves data to a CSV file based on the given URL.
#  *
#  *  @param $finalUrl   String   CSV Download URI.
#  *  @param $finalName  String   Filepointer to save location.
sub SaveData {
	my ($self, $finalUrl, $finalName) = @_;
	my $data = $self->GetData($finalUrl);

	if (length $data > 1) {
		$log->info("Success!!!");
		my $contents = decode 'UTF-8', $data;
		# $log->info(Dumper($contents));

		$log->info("Final name: $finalName");
		
		my $fh;
		open($fh, '>', $finalName) or die "Couldn't open: $!";
		print $fh $contents;
		close $fh;
		push $self->{'_downloaded'}, $finalName;
		return 1;
	} else {
		$log->info("Skipped $finalName");
		push $self->{'_skipped'}, $finalName;
		return;
	}
}

# *  Regular Expression to find the Security Token for a download file.
# *
# *  @param $uri        String   A Webmaster Tools Desktop Service URI.
# *  @param $delimiter  String   Trailing delimiter for the regex.
# *  @return  String    Returns a security token.

sub GetToken {
	my ($self, $uri, $delimiter, $dlUri) = @_;
	my $match;
	my $tmp = $self->GetData($uri);

	if ($tmp =~ m{$dlUri.*?46security_token(.*?)'}si) {
		my $sec_token = $1;
		$sec_token =~ s!^\\+[0-9]{2}!!;
		$match = $sec_token;
	}

	return $match;
}

# *  Validates ISO 8601 date format.
# *
# *  @param $str      String   Valid ISO 8601 date string (eg. 2012-01-01).
# *  @return  Boolean   Returns true if string has valid format, else false.
		 
# sub IsISO8601 {
# 	my ($self, $str) = @_;
# 	my $stamp = strtotime($str);
# 	return (is_numeric($stamp) && checkdate(date('m', $stamp),
# 		  date('d', $stamp), date('Y', $stamp))) ? true : false;
# }


1;
