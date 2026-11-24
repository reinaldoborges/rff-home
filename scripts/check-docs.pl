#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(abs_path);
use Encode qw(decode encode FB_CROAK);
use File::Basename qw(dirname);
use File::Spec;

binmode STDERR, ':encoding(UTF-8)' or die "set stderr encoding: $!";

open my $git, '-|', 'git', 'ls-files', '-z', '--cached', '--others',
    '--exclude-standard', '--', '*.md' or die "run git ls-files: $!";
local $/ = "\0";
my @files = <$git>;
close $git or die "git ls-files failed\n";
chomp @files;
local $/ = "\n";

my %anchor_cache;
my $errors = 0;

sub lines_of {
    my ($path) = @_;
    open my $file, '<:encoding(UTF-8)', $path or die "read $path: $!";
    my @lines = <$file>;
    close $file or die "close $path: $!";
    return @lines;
}

sub unfenced_lines {
    my ($path, $report) = @_;
    my @lines = lines_of($path);
    my ($marker, $opened);
    for my $i (0 .. $#lines) {
        my $line = $lines[$i];
        if (defined $marker) {
            my $char = substr($marker, 0, 1);
            undef $marker if $line =~ /^ {0,3}\Q$marker\E\Q$char\E*\s*$/;
            $lines[$i] = '';
        } elsif ($line =~ /^ {0,3}(`{3,}|~{3,})(.*)$/) {
            my ($candidate, $info) = ($1, $2);
            next if substr($candidate, 0, 1) eq '`' && $info =~ /`/;
            ($marker, $opened) = ($candidate, $i + 1);
            $lines[$i] = '';
        }
    }
    if (defined $marker && $report) {
        warn "$path:$opened: unclosed code fence\n";
        $errors++;
    }
    return @lines;
}

sub anchors_for {
    my ($path) = @_;
    return $anchor_cache{$path} if exists $anchor_cache{$path};
    my (%anchors, %used);
    my @lines = $path =~ /\.md$/i ? unfenced_lines($path, 0) : lines_of($path);
    for my $line (@lines) {
        while ($line =~ /\b(?:id|name)=["']([^"']+)["']/g) {
            $anchors{$1} = 1;
        }
        next unless $path =~ /\.md$/i && $line =~ /^ {0,3}#{1,6}\s+(.+?)\s*$/;
        my $title = $1;
        $title =~ s/\s+#+\s*$//;
        $title =~ s/\[([^\]]+)\]\([^)]+\)/$1/g;
        $title =~ s/<[^>]+>//g;
        $title = lc $title;
        $title =~ s/[^\p{L}\p{N}\p{M} _-]//g;
        $title =~ s/ /-/g;
        my $anchor = $title;
        my $suffix = 0;
        $anchor = "$title-" . ++$suffix while $used{$anchor};
        $used{$anchor} = 1;
        $anchors{$anchor} = 1;
    }
    return $anchor_cache{$path} = \%anchors;
}

sub check_link {
    my ($source, $line, $link) = @_;
    return if $link =~ m{^[a-z][a-z0-9+.-]*:}i || $link =~ m{^//};
    my ($path, $fragment) = split /#/, $link, 2;
    $path =~ s/\?.*$//;
    for ($path, $fragment) {
        next unless defined;
        my $bytes = encode('UTF-8', $_);
        $bytes =~ s/%([0-9a-f]{2})/chr hex $1/gei;
        $_ = decode('UTF-8', $bytes, FB_CROAK);
    }
    my $target = length($path)
        ? File::Spec->rel2abs(encode('UTF-8', $path), dirname(File::Spec->rel2abs($source)))
        : File::Spec->rel2abs($source);
    if (!-e $target) {
        warn "$source:$line: missing local link $link\n";
        $errors++;
        return;
    }
    if (defined $fragment && length $fragment && -f $target) {
        my $resolved = abs_path($target);
        unless (anchors_for($resolved)->{$fragment}) {
            warn "$source:$line: missing anchor in $link\n";
            $errors++;
        }
    }
}

for my $file (@files) {
    next unless -f $file;
    my @lines = unfenced_lines($file, 1);
    for my $i (0 .. $#lines) {
        my $line = $lines[$i];
        $line =~ s/(`+).*?\1//g;
        if ($line =~ /^ {0,3}\[[^\]]+\]:\s*(?:<([^>]+)>|(\S+))/) {
            check_link($file, $i + 1, defined $1 ? $1 : $2);
        }
        while ($line =~ /\]\(\s*(?:<([^>]+)>|((?:\\.|[^()\s]|\([^()]*\))+))(?=\s|\))/g) {
            check_link($file, $i + 1, defined $1 ? $1 : $2);
        }
    }
}
exit($errors ? 1 : 0);
