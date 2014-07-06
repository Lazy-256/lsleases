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

my ($commit, $no_build, $no_test, $keep_vms_up, $verbose);
GetOptions("c|commit=s" => \$commit,
           "nb|no-build" => \$no_build,
           "nt|no-test" => \$no_test,
           "k|keep-vms-up" => \$keep_vms_up,
           "v|verbose" => \$verbose);

#
# validate args
#
die "unkow parameter" if $#ARGV >=0;

my $build_packages_vm_name = "debian-i386-jenkins";
my $build_packages_job_name = "lsleases-packages";

my @integration_test_vms_names = qw/fedora-i386-jenkins fedora-amd64-jenkins ubuntu-1404-i386-jenkins ubuntu-1404-amd64-jenkins xp-jenkins/;
my $integration_test_job_name = "lsleases-integration-test";


my $base_dir = file(__FILE__)->parent->parent->absolute;
my $build_output = "$base_dir/build-output";

# autoflush
$OUTPUT_AUTOFLUSH = 1;


#
say "# startup build vm";
startup_vm($build_packages_vm_name);
wait_for_vm_is_up($build_packages_vm_name);
my $build_packages_vm_ip = lookup_ip($build_packages_vm_name);



#
# build
#
if( ! $no_build){

    #
    say "# trigger local build";
    my $build_pl_args = (defined($commit) ? "-c $commit" : "");
    system("${base_dir}/build-scripts/build.pl $build_pl_args");
    
    #
    say "# trigger build in vm: $build_packages_vm_name ($build_packages_vm_ip)";
    my $job_parameters = (defined($commit) ? "COMMIT=${commit}" : "COMMIT=HEAD");
    my ($build_result, $build_url, $build_output) = trigger_jenksins_build($build_packages_vm_ip, $build_packages_job_name, $job_parameters);
    if($build_result ne "SUCCESS"){
        say $build_output;
        say "-" x 80;
        die "BUILD FAILED IN VM: $build_packages_vm_name ($build_packages_vm_ip) $build_url";
    }
    say $build_output if defined($verbose);
}


#
# integration test
#
if ( ! $no_test){
    #
    say "# startup integration test vms";
    startup_vms(@integration_test_vms_names);
    wait_for_vm_is_up($_) for(@integration_test_vms_names);
    my %integration_test_vms_ips = %{collect_vm_ips(@integration_test_vms_names)};

    say "# trigger integration tests";
    for my $vm (@integration_test_vms_names){
        my $ip = $integration_test_vms_ips{$vm};

        say "- trigger integration tests in vm: $vm ($ip)";
        my $jenkins_packages_builder_url = "http://${build_packages_vm_ip}:8080/job/${build_packages_job_name}";
        my ($build_result, $build_url, $build_output) =
            trigger_jenksins_build($ip, $integration_test_job_name, "JENKINS_PACKAGES_BUILDER_URL=$jenkins_packages_builder_url");

        if($build_result ne "SUCCESS"){
            say $build_output;
            say "-" x 80;
            die "BUILD FAILED IN VM: $vm ($ip) - $build_url";
        }

        say $build_output if defined($verbose);
    }

    if(! defined($keep_vms_up)){
      #
      say "# shutdown integration test vms";
      shutdown_vms(@integration_test_vms_names);
    }
}



#
# get build artifacts
#

#
print "# fetch build artifacts ";
my $ua = LWP::UserAgent->new;
my $attempt = 0;
while($ua->mirror("http://${build_packages_vm_ip}:8080/job/${build_packages_job_name}/lastBuild/artifact/*zip*/archive.zip", "${base_dir}/archive.zip")->code != 200){
    die " timeout" if($attempt++ >= 120);
    print ".";
    sleep(1);
}
print "\n";

#
say "# unzip artifacts to ${build_output}";
system("unzip -ojd ${build_output} ${base_dir}/archive.zip");
unlink("${base_dir}/archive.zip");


if(! defined($keep_vms_up)){
  #
  shutdown_vm($build_packages_vm_name);
}









sub startup_vms{
    my @vms = @_;

    for my $vm (@vms){
        startup_vm($vm);
    }
}

sub startup_vm{
    my $vm = shift;
    say "- startup $vm";
    system("VBoxHeadless -s $vm >/dev/null 2>&1 &");
}

sub shutdown_vms{
    my @vms = @_;
    
    for my $vm(@vms){
        shutdown_vm($vm);
    }
}

sub shutdown_vm{
    my $vm = shift;
    
    say "- shutdown $vm";
    system("VBoxManage controlvm $vm acpipowerbutton");
}



sub collect_vm_ips{
    my @vms = @_;

    my %ips;
    for my $vm(@vms){
        $ips{$vm} = lookup_ip($vm);
    }
    return \%ips;
}

sub wait_for_vm_is_up {
    my $vm_name = shift;

    print "- wait for vm: $vm_name is up .";
    while(1){
        my $vm_ip = lookup_ip($vm_name);
        if(system("ping -c 1 $vm_ip > /dev/null 2>&1") == 0){
            print "\n";
            last;
        }
        print ".";
        sleep(1);
    }
}

sub lookup_ip {
    my $host_name = shift;

    while(1){
        my $lsleases_output = `lsleases -H | grep $host_name`;
        if(length($lsleases_output) > 0){
            my $host_ip = shift([split(/\s/, $lsleases_output)]);
            return $host_ip;
        }
        print ".";
        sleep(1);
    }
}




sub trigger_jenksins_build{
    my $jenkins_ip = shift;
    my $job_name = shift;
    my $job_parameters = shift;

    my $url;
    if(defined($job_parameters)){
        $url = "http://${jenkins_ip}:8080/job/${job_name}/buildWithParameters?$job_parameters";
    }else{
        $url = "http://${jenkins_ip}:8080/job/${job_name}/build"; 
    }

    my $ua = LWP::UserAgent->new;
    say "call $url";
    my  $response = $ua->get($url);


    print "wait till jenkins is up ." if($response->code != 201);
    my $counter = 0;
    while($response->code != 201){
        print ".";
        sleep(1);
        
        die " timeout " if($counter++ >= 180);
        $response = $ua->get($url);
    }
    print "\n";

    
    if(! $response->is_success){
        return ($response->status_line, "", "");
    }

    my $queue_item_location = $response->header("Location");
    my $queue_item_json;
    print "  - queued .";
    do{
        $queue_item_json = Load($ua->get("${queue_item_location}/api/json")->content);
        print ".";
        sleep 1;
    }while(! defined $queue_item_json->{executable});
    say "";

    my $build_item_location = $queue_item_json->{executable}->{url};
    my $build_item_json;
    print "  - building .";
    do{
        $build_item_json = Load($ua->get("${build_item_location}/api/json")->content);
        print ".";
        sleep 1;
    }while($build_item_json->{building});
    say "";

    my $build_item_output = $ua->get($build_item_json->{url} . "/logText/progressiveText")->content;

    return ($build_item_json->{result}, $build_item_location, $build_item_output);

}


#
# extracts the version from lsleases.go
#
sub extractVersion {
    my $file = shift;
    open(my $fh, "<$file");
    my ($version_line) = grep /.*VERSION.*/, <$fh>;
    close($fh);

    die "version line not found" if(! defined $version_line);
    $version_line =~ /VERSION\s*=\s*"(.*)"/;
    die "version not found" if(! defined $1);

    return $1;
}
