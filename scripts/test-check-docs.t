use strict;
use warnings;
use utf8;
use Cwd qw(abs_path getcwd);
use Encode qw(encode);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

my $checker = abs_path('scripts/check-docs.pl');
ok(defined $checker, 'documentation checker exists');
BAIL_OUT('checker is missing') unless defined $checker;
my $repo = tempdir(CLEANUP => 1);
is(system('git', '-C', $repo, 'init', '-q'), 0, 'create temporary repository');

sub write_file {
    my ($path, $contents) = @_;
    my $name = "$repo/" . encode('UTF-8', $path);
    if ($name =~ m{^(.*)/[^/]+$}) {
        make_path($1);
    }
    open my $file, '>', $name or die "write $name: $!";
    binmode $file, ':encoding(UTF-8)' or die "set encoding $name: $!";
    print {$file} $contents;
    close $file or die "close $name: $!";
}

sub check_docs {
    my $previous = getcwd();
    chdir $repo or die "chdir $repo: $!";
    my ($out, $err);
    $err = gensym;
    my $pid = open3(undef, $out, $err, $^X, $checker);
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    waitpid($pid, 0);
    my $status = $? >> 8;
    chdir $previous or die "chdir $previous: $!";
    return ($status, $stdout . $stderr);
}

write_file('.gitignore', "ignored/\n");
write_file('target.md', "# Two words\n# Café\n# Repeated\n# Repeated\n");
write_file('café.md', "# Café\n");
write_file('images/a b.png', '');
write_file('guide.md', <<'DOC');
# Intro
[relative](target.md#two-words)
[encoded fragment](target.md#caf%C3%A9)
[encoded file](caf%C3%A9.md#café)
[duplicate heading](target.md#repeated-1)
[same file](#intro)
![image](<images/a b.png>)
[reference][target]
[target]: target.md#two-words
[external](https://example.com/not-local)
````text
[not a link](missing.md)
```
````
DOC
write_file('ignored/generated.md', "[ignored](missing.md)\n```\n");
my ($status, $output) = check_docs();
is($status, 0, "valid links and fences pass: $output");

write_file('broken.md', "[missing](missing.md)\n");
($status, $output) = check_docs();
isnt($status, 0, 'missing local file fails');
like($output, qr/broken\.md:1.*missing\.md/, 'missing link identifies location');

write_file('broken.md', "[bad anchor](target.md#not-there)\n");
($status, $output) = check_docs();
isnt($status, 0, 'missing local anchor fails');
like($output, qr/broken\.md:1.*not-there/, 'missing anchor identifies location');

write_file('broken.md', "```go\n[not a link](missing.md)\n");
($status, $output) = check_docs();
isnt($status, 0, 'unclosed fence fails');
like($output, qr/broken\.md:1.*fence/i, 'unclosed fence identifies opening');

done_testing();
