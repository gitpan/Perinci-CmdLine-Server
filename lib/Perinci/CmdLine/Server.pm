package Perinci::CmdLine::Server;

use 5.010001;
use strict;
use warnings;
#use Log::Any '$log';

sub import {
    my $pkg = shift;

    my $caller = caller;

    while (@_) {
        my $arg = shift @_;
        if ($arg =~ /\A(create_cmdline_server)\z/) {
            no strict 'refs';
            *{"$caller\::$arg"} = \&{$arg};
        } elsif ($arg =~ /\A-(.+)\z/) {
            my $name = $1;
            die "Invalid app name $name" unless $name =~ /\A\w+\z/;
            die "$arg requires argument" unless @_;
            my $url = shift;
            create_cmdline_server(name => $name, cmdline_args => {url=>$url});
        } else {
            die "$arg is not imported by ".__PACKAGE__;
        }
    }
}

our %SPEC;

$SPEC{create_cmdline_server} = {
    v => 1.1,
    summary => 'Create Perinci::CmdLine object and '.
        'some functions to access it in a Perl package',
    description => <<'_',

Currently the functions created are:

    complete_cmdline

_
    args => {
        name => {
            summary => 'Application name',
            description => <<'_',

This function stores the created functions in a hash, keyed by name. If you
create an application with the same name as previously created, the previous
instance will be replaced.

_
            schema  => ['str*', match => '\A\w+\z'],
            req     => 1,
            pos     => 0,
        },
        cmdline_args => {
            summary => 'Arguments to be fed to Perinci::CmdLine constructor',
            schema  => [hash => default => {}],
        },
        package => {
            summary => 'Where to put the functions to access the object',
            description => <<'_',

The default is `Perinci::CmdLine::Server::app::` + `<name>`. But you can put it
somewhere else. The functions will be installed here.

_
        },
    },
    result_naked => 1,
};
sub create_cmdline_server {
    require Perinci::CmdLine;

    my %cargs = @_;

    # store created cli's by name
    state $clis = {};

    my $name    = $cargs{name} or die "Please specify CLI app name";
    $name =~ /\A\w+\z/ or die "Invalid name, please use alphanumeric only";
    my $package = $cargs{package} // 'Perinci::CmdLine::Server::app::' . $name;

    my $cli = Perinci::CmdLine->new(
        %{ $cargs{cmdline_args} // {} },
        exit => 0,
    );

    # create the functions to access the CLI
    {
        no strict 'refs';
        ${"$package\::SPEC"}{complete_cmdline} = {
            v => 1.1,
            summary => 'Complete command-line application',
            description => <<'_',

Currently only supports bash.

_
            args => {
                cmdline => {
                    summary => 'Command-line string, usually from COMP_LINE',
                    schema  => 'str*',
                    req     => 1,
                    pos     => 0,
                },
                point => {
                    summary => 'Cursor position in command-line, usually from COMP_POINT',
                    schema  => 'int*',
                    req     => 1,
                    pos     => 1,
                },
            },
            result => {
                schema => 'str*',
            },
        };
        *{"$package\::complete_cmdline"} = sub {
            my %fargs = @_;
            local $ENV{COMP_LINE}  = $fargs{cmdline};
            local $ENV{COMP_POINT} = $fargs{point};
            local $ENV{PERINCI_CMDLINE_SERVER} = 1;
            $cli->run();
            [200, "OK", $cli->{_compres}];
        };
    }

    $clis->{$name} = [$cli, $package];

    $cli;
}

our $DATE = '2014-07-03'; # DATE
our $VERSION = '0.01'; # VERSION

1;
# ABSTRACT: Create CLI application instance and functions to access it

__END__

=pod

=encoding UTF-8

=head1 NAME

Perinci::CmdLine::Server - Create CLI application instance and functions to access it

=head1 VERSION

This document describes version 0.01 of Perinci::CmdLine::Server (from Perl distribution Perinci-CmdLine-Server), released on 2014-07-03.

=head1 SYNOPSIS

 use Perinci::CmdLine::Server qw(create_cmdline_server);
 create_cmdline_server(
     name         => 'app1',
     cmdline_args => {
         url         => '/Some/Module/some_func',
         log_any_app => 0,
     },
 );

Shortcut for simple cases:

 use Perinci::CmdLine::Server -app1 => '/Some/Module/some_func';

From command-line:

 % perl -MPerinci::CmdLine::Server=-app1,/Some/Module/some_func ...

=head1 DESCRIPTION

Currently, L<Perinci::CmdLine>-based CLI applications have a perceptible startup
overhead (between 0.15-0.35s or even more, depending on your hardware, those
numbers are for 2011-2013 PC/laptop hardware). Some of the cause of the overhead
is subroutine wrapping (see L<Perinci::Sub::Wrapper>) which also involves
compilation of L<Sah> schemas (see L<Data::Schema>), all of which are necessary
for the convenience of using L<Rinci> metadata to specify aspects of your
functions.

This level of overhead is a bit annoying when we are doing shell tab completion
(Perinci::CmdLine-based applications call themselves for doing tab completion,
e.g. through bash's C<complete -C progname progname> mechanism). Ideally,
tab completion should take no longer than 0.05-0.1s to feel instantaneous.

One (temporary?) solution to this annoyance is to start a daemon that listens to
L<Riap> requests (either through Unix domain sockets or TCP/IP). This way, the
completion external command can just be a lightweight HTTP client which asks the
server for the completion and displays the result to STDOUT for bash (this only
requires, e.g. L<HTTP::Tiny::Unix> + L<Complete::Bash>).

In the future, other functionalities aside from completion can also be
"off-loaded" to the server side to make the CLI program lighter and quicker to
start. This might require a refactoring of Perinci::CmdLine codebase so it's
more "stateless" and reusable/safer for multiple requests (perhaps will be made
non-OO in the core so it's clear what states are being passed?)

In the future, Perinci::CmdLine can also be configured to automatically start a
daemon after the first run (and retire/kill the daemon after being idle for,
say, 30 minute or an hour).

=head2 How does it work?

In your L<Perinci::Access::HTTP::Server>-based PSGI application:

 use Perinci::CmdLine::Server qw(create_cmdline_server);
 create_cmdline_server(
     name         => 'app1',
     cmdline_args => {
         url         => '/Some/Module/some_func',
         log_any_app => 0,
     },
 );

This will create an instance of Perinci::CmdLine object (the C<cmdline_args>
argument will be fed to the constructor). It will also create a Perl package
dynamically (the default is C<Perinci::CmdLine::Server::app::> + application
name specified in C<name> argument). The package will contain several functions
along with their L<Rinci> metadata. The functions can then be accessed over
L<Riap> protocol. So far, the only function available is: C<complete_cmdline>.
You can use it to request command-line completion. The Perinci::CmdLine object
will persist as long as the process lives. You can of course start several
applications.

=head2 Caveats

Leaving daemons around could give rise to some security and resource-usage
issues. It is ideal in situations where you already have a daemon for other
purposes (for example, in Spanel there is already an API daemon service running;
the command-line client uses this daemon to request for tab completion).

Some code which normally runs on the client-side will now run on the
server-side. For example, the C<custom_completer> and C<custom_arg_completer>
code. You have to make sure that authentication and authorization issues are
handled.

=head1 FUNCTIONS


=head2 create_cmdline_server(%args) -> any

Create Perinci::CmdLine object and some functions to access it in a Perl package.

Currently the functions created are:

    complete_cmdline

Arguments ('*' denotes required arguments):

=over 4

=item * B<cmdline_args> => I<hash> (default: {})

Arguments to be fed to Perinci::CmdLine constructor.

=item * B<name>* => I<str>

Application name.

This function stores the created functions in a hash, keyed by name. If you
create an application with the same name as previously created, the previous
instance will be replaced.

=item * B<package> => I<any>

Where to put the functions to access the object.

The default is C<Perinci::CmdLine::Server::app::> + C<<name>>. But you can put it
somewhere else. The functions will be installed here.

=back

Return value:

=for Pod::Coverage ^(import)$

=head1 SEE ALSO

L<Perinci::CmdLine>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Perinci-CmdLine-Server>.

=head1 SOURCE

Source repository is at L<https://github.com/sharyanto/perl-Perinci-CmdLine-Server>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Perinci-CmdLine-Server>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
