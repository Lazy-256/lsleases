#!/usr/bin/env perl
#
#
#
use v5.14;
use strict;
use warnings;
use diagnostics;
use LWP::UserAgent;
use local::lib;
use YAML::XS qw/Load Dump/;
use Getopt::Long;
use Path::Class;
use English;

my ($commit, $publish_bt, $publish_gh);
GetOptions("c|commit=s" => \$commit,
           "pub-bt|publish-bintray" => \$publish_bt,
           "pub-gh|publish-github" => \$publish_gh);

die "'commit' needed" unless defined($commit);
die "'GITHUB_TOKEN' not found!" unless defined($ENV{GITHUB_TOKEN});
die "'BINTRAY_TOKEN' not found!" unless defined($ENV{BINTRAY_TOKEN});


my $base_dir = file(__FILE__)->parent->parent->absolute;
my $build_output = "$base_dir/build-output";


#
# publish!
#
if(defined($publish_gh)){
    publish_github();
}elsif(defined($publish_bt)){
    publish_bintray();
}else{
  publish_github();
  publish_bintray();
}



sub publish_github {
    
    say "# publish github";
    die "no 'commit' given!" unless defined($commit);

    my $release_cmd_gh = "perl $base_dir/build-scripts/github-release.pl create -u j-keck -r lsleases  -raw-json -t $commit";
    say $release_cmd_gh;
    my $release_gh = Load(`$release_cmd_gh`);
    say Dump $release_gh;
    die "create release error" unless(defined($release_gh->{id}));

    my $upload_cmd_gh = "perl $base_dir/build-scripts/github-release.pl upload-dir -u j-keck -r lsleases -t $commit -i $release_gh->{id} -d $build_output";
    say $upload_cmd_gh;
    system($upload_cmd_gh);
}

sub publish_bintray {

    say "# publish bintray";
    die "no 'commit' given!" unless defined($commit);

    my $relase_cmd_bt = "perl $base_dir/build-scripts/bintray.pl create -u j-keck -p lsleases -t $commit";
    say $relase_cmd_bt;
    system($relase_cmd_bt);

    my $upload_cmd_bt = "perl $base_dir/build-scripts/bintray.pl upload-dir -u j-keck -p lsleases -t $commit -d $build_output";
    say $upload_cmd_bt;
    system($upload_cmd_bt);

    my $publish_cmd_bt = "perl $base_dir/build-scripts/bintray.pl publish -u j-keck -p lsleases -t $commit";
    say $publish_cmd_bt;
    system($publish_cmd_bt);
}

