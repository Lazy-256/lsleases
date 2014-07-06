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

my ($user, $repo, $release_id, $token, $file_path, $dir, $tag_name, $dump_raw_json);

GetOptions("u|user=s" => \$user,
           "r|repo=s" => \$repo,
           "token=s" => \$token,           
           "i|id=i" => \$release_id,
           "f|file=s" => \$file_path,
           "d|dir=s" => \$dir,
           "t|tag=s" => \$tag_name,
           "rj|raw-json" => \$dump_raw_json);


# get mode - exit if no mode given
my $mode = shift;
say_and_exit("'mode' required") unless defined($mode);


# get base params from env if not given per args
$user = $ENV{GITHUB_USER} unless defined($user);
$repo = $ENV{GITHUB_REPO} unless defined($repo);
$token = $ENV{GITHUB_TOKEN} unless defined($token);

say_and_exit("no 'user' given!") unless defined($user);
say_and_exit("no 'repo' given!") unless defined($repo);


# action
#  * base params are used from global scope
info() if $mode eq "info";
create($tag_name) if $mode eq "create";
del($release_id) if $mode eq "delete";
upload($release_id, $file_path) if $mode eq "upload";
upload_dir($release_id, $dir) if $mode eq "upload-dir";


sub info {
    my $ua = LWP::UserAgent->new;

    my $content = $ua->get("https://api.github.com/repos/${user}/${repo}/releases")->content;

    if(defined($dump_raw_json)){
        say $content;
    }else{
        my @releases = @{Load($content)};
        for my $release(@releases){
            say "name: $release->{name}, tag_name: $release->{tag_name}, id: $release->{id}";
            for my $asset(@{$release->{assets}}){
                say "  id: $asset->{id}, name: $asset->{name}, download_count: $asset->{download_count}";
            }
        }
    }
}

sub create{
    my $tag_name = shift;

    say_and_exit("no 'tag' given!") unless defined($tag_name);
    
    my $url = "https://api.github.com/repos/${user}/${repo}/releases?access_token=${token}";
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(POST => $url);
    $request->content(qq/{"tag_name": "$tag_name", "name": "$tag_name"}/);
    $request->header("ContentType" => "application/json");
    my $content = $ua->request($request)->content;

    if(defined($dump_raw_json)){
        say $content;
    }else{
        say Dump Load($content);
    }
}

sub del{
    my $release_id = shift;

    say_and_exit("no 'id' given!") unless defined($release_id);
    say_and_exit("no 'token' given!") unless defined($token);

    my $url = "https://api.github.com/repos/${user}/${repo}/releases/${release_id}?access_token=${token}";
    my $ua = LWP::UserAgent->new;
    my $content = $ua->delete($url)->content;
    say $content;  
}
    

    


sub upload{
    my $release_id = shift;
    my $file_path = shift;

    say_and_exit("no 'id' given!") unless defined($release_id);
    say_and_exit("no 'file' given!") unless defined($file_path);
    say_and_exit("no 'token' given!") unless defined($token);

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

    my $url = "https://uploads.github.com/repos/${user}/${repo}/releases/${release_id}/assets?name=${file_name}&access_token=${token}";
    my $request = HTTP::Request->new(POST => $url);
    $request->header("Content-Type" => "application/octet-stream");
    $request->content($file_content);  
    
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($request);
    say $response->message;
}

sub upload_dir{
    my $release_id = shift;
    my $dir = shift;

    say_and_exit("no 'id' given!") unless defined($release_id);
    say_and_exit("no 'dir' given!") unless defined($dir);
    say_and_exit("no 'token' given!") unless defined($token);    

    my $find_callback = sub{
        my $file_path = $File::Find::name;
        if( -f $file_path){
            upload($release_id, $file_path);
        }
    };
    find({wanted => $find_callback, no_chdir => 1}, $dir);
}



sub say_and_exit{
    say @_;
    exit 1;
}
