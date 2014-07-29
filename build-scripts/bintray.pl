use v5.14;
use local::lib;
use autodie;
use diagnostics;
use LWP::UserAgent;
use HTTP::Request;
use YAML::XS qw/Load Dump/;
use Getopt::Long;
use File::Find;
use Cwd qw/abs_path/;

my %suffix_repo_mapping = (
    deb => "deb",
    rpm => "rpm",
    txz => "FreeBSD",
    zip => "windows",
    exe => "windows");

my ($user, $token, $pkg, $file, $dir, $tag_name, $dump_raw_json);

GetOptions("u|user=s" => \$user,
           "token=s" => \$token,
           "p|package=s" => \$pkg,
           "f|file=s" => \$file,
           "d|dir=s" => \$dir,
           "t|tag=s" => \$tag_name,
           "rj|raw-json" => \$dump_raw_json);


# get mode - exit if no mode given
my $mode = shift;
say_and_exit("'mode' required") unless defined($mode);


# get base params from env if not given per args
$user = $ENV{BINTRAY_USER} unless defined($user);
$token = $ENV{BINTRAY_TOKEN} unless defined($token);

say_and_exit("no 'user' given!") unless defined($user);
say_and_exit("no 'token' given!") unless defined($token);


# action
#  * base params are used from global scope
info($pkg) if $mode eq "info";
logs($pkg) if $mode eq "log";
create($pkg, $tag_name) if $mode eq "create";
del($pkg, $tag_name) if $mode eq "delete";
upload($pkg, $tag_name, $file) if $mode eq "upload";
upload_dir($pkg, $tag_name, $dir) if $mode eq "upload-dir";
publish($pkg, $tag_name) if $mode eq "publish";

sub info{
    my $pkg = shift;

    say_and_exit("no 'package' given!") unless defined($pkg);
    
    for my $repo(qw/deb rpm FreeBSD windows/){
        my $url = "https://api.bintray.com/packages/${user}/${repo}/${pkg}";
        say $url;
        my $request = HTTP::Request->new(GET => $url);
        $request->authorization_basic($user, $token);
        
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($request);
        if(defined($dump_raw_json)){
            say $response->content;
        }else{
            say Dump Load($response->content);
        }
    }
}

sub logs{
    my $pkg = shift;

    say_and_exit("no 'package' given!") unless defined($pkg);
    
    for my $repo(qw/deb rpm FreeBSD windows/){
        my $url = "https://api.bintray.com/packages/${user}/${repo}/${pkg}/logs";
        say $url;
        my $request = HTTP::Request->new(GET => $url);
        $request->authorization_basic($user, $token);
        
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($request);
        if(defined($dump_raw_json)){
            say $response->content;
        }else{
            say Dump Load($response->content);
        }
    }
}


sub create{
    my $pkg = shift;
    my $tag_name = shift;

    say_and_exit("no 'package' given!") unless defined($pkg);
    say_and_exit("no 'tag' given!") unless defined($tag_name);

    
    for my $repo(qw/deb rpm FreeBSD windows/){
        my $url = "https://api.bintray.com/packages/${user}/${repo}/${pkg}/versions";
        my $request = HTTP::Request->new(POST => $url);
        $request->header("Content-Type" => "application/json");
        $request->content(qq({"name": "$tag_name"}));
        $request->authorization_basic($user, $token);
        
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($request);
        if(defined($dump_raw_json)){
            say $response->content;
        }else{
            say Dump Load($response->content);
        }
    }
}

sub del{
    my $pkg = shift;
    my $tag_name = shift;

    say_and_exit("no 'package' given!") unless defined($pkg);
    say_and_exit("no 'tag' given!") unless defined($tag_name);

    
    for my $repo(qw/deb rpm FreeBSD windows/){
        my $url = "https://api.bintray.com/packages/${user}/${repo}/${pkg}/versions/${tag_name}";
        say $url;
        my $request = HTTP::Request->new(DELETE => $url);
        $request->authorization_basic($user, $token);
        
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($request);
        if(defined($dump_raw_json)){
            say $response->content;
        }else{
            say Dump Load($response->content);
        }
    }
}




sub upload{
    my $pkg = shift;
    my $tag_name = shift;
    my $file_path = shift;

    say_and_exit("no 'package' given!") unless defined($pkg);
    say_and_exit("no 'tag' given!") unless defined($tag_name);
    say_and_exit("no 'file' given!") unless defined($file_path);

    # extract file suffix
    my $file_suffix = pop([split(/\./, $file_path)]);
    die "file suffix not found" unless defined($file_suffix);
    my $repo = $suffix_repo_mapping{$file_suffix};
    die "repo not found" unless defined($repo);

    # extract file name
    my $file_name = pop([split(q^/^, $file_path)]);

    say "upload ${file_path} as ${file_name}";

    # read the file
    open(fh, "<$file_path");
    binmode(fh);
    my ($file_content, $buffer, $n);
    while(($n = read(fh, $buffer, 512)) != 0){
        $file_content .= $buffer;
    }
    
    
    my $url = "https://api.bintray.com/content/${user}/${repo}/${pkg}/${tag_name}/${file_name}";
    say $url;
    my $request = HTTP::Request->new(PUT => $url);
    $request->header("Content-Type" => "application/octet-stream");
    $request->content($file_content);  
    $request->authorization_basic($user, $token);
    
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($request);
    if(defined($dump_raw_json)){
        say $response->content;
    }else{
        say Dump Load($response->content);
    }

}



sub upload_dir{
    my $pkg = shift;
    my $tag_name = shift;
    my $dir = shift;

    say_and_exit("no 'package' given!") unless defined($pkg);
    say_and_exit("no 'dir' given!") unless defined($dir);

    my $find_callback = sub{
        my $file_path = $File::Find::name;
        if( -f $file_path){
            upload($pkg, $tag_name, $file_path);
        }
    };
    find({wanted => $find_callback, no_chdir => 1}, $dir);
}



sub publish{
    my $pkg = shift;
    my $tag_name = shift;

    say_and_exit("no 'package' given!") unless defined($pkg);
    say_and_exit("no 'tag' given!") unless defined($tag_name);

    
    for my $repo(qw/deb rpm FreeBSD windows/){
        my $url = "https://api.bintray.com/content/${user}/${repo}/${pkg}/${tag_name}/publish";
        say $url;
        my $request = HTTP::Request->new(POST => $url);
        $request->authorization_basic($user, $token);
        
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($request);
        if(defined($dump_raw_json)){
            say $response->content;
        }else{
            say Dump Load($response->content);
        }
    }
}



sub say_and_exit{
    say @_;
    exit 1;
}
