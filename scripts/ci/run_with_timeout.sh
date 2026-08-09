#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 || ! "$1" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: $0 <positive-seconds> <command> [arguments...]" >&2
  exit 64
fi

TIMEOUT_SECONDS="$1"
shift

exec /usr/bin/perl -MPOSIX=setsid,WNOHANG -MTime::HiRes=time,sleep -e '
  use strict;
  use warnings;

  my $seconds = shift @ARGV;
  pipe(my $ready_reader, my $ready_writer)
    or die "unable to create bounded command readiness pipe: $!\n";

  my $child_pid = fork();
  die "unable to fork bounded command: $!\n" unless defined $child_pid;

  if ($child_pid == 0) {
    close $ready_reader;
    my $session_id = setsid();
    if (!defined $session_id || $session_id < 0) {
      print {$ready_writer} "error:$!\n";
      close $ready_writer;
      exit 125;
    }
    print {$ready_writer} "ready\n";
    close $ready_writer;
    exec @ARGV;
    warn "unable to execute bounded command: $!\n";
    exit 127;
  }

  close $ready_writer;
  my $ready_state = <$ready_reader>;
  close $ready_reader;
  if (!defined $ready_state || $ready_state ne "ready\n") {
    waitpid($child_pid, 0);
    exit 125;
  }

  my $deadline = time() + $seconds;
  while (time() < $deadline) {
    my $waited_pid = waitpid($child_pid, WNOHANG);
    if ($waited_pid == $child_pid) {
      my $status = $?;
      exit (($status & 127) ? 128 + ($status & 127) : $status >> 8);
    }
    die "unable to wait for bounded command: $!\n" if $waited_pid == -1;
    sleep 0.05;
  }

  kill "TERM", -$child_pid;
  my $termination_deadline = time() + 0.5;
  while (time() < $termination_deadline) {
    my $waited_pid = waitpid($child_pid, WNOHANG);
    if ($waited_pid == $child_pid) {
      kill "KILL", -$child_pid;
      exit 124;
    }
    last if $waited_pid == -1;
    sleep 0.05;
  }

  kill "KILL", -$child_pid;
  waitpid($child_pid, 0);
  exit 124;
' "$TIMEOUT_SECONDS" "$@"
