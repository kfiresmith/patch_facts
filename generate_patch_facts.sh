#!/bin/bash
#
# Variables created:
#  - OS-Release (string)
#  - Security errata support (boolean)
#  - EOL (boolean)
#  - All Outstanding Packages Count (integer)
#  - Security Outstanding Packages Count (integer)
#  - ISO-8601 Date of Collection (string)
#
# 2021-04-18 Kodiak Firesmith <firesmith@protonmail.com>

# Don't let this script run w/o the ability to do things like update the package
#  cache.  And don't accidentally blow out /var/cache with non-root duplicates
#  of YUM caches.
if [ $USER != root ]; then
  echo "this script requires rootly powers"
  exit 2
fi

# Simple ISO-8601 date
date_collected="$(date -I)"

# By default, assume OS updates are not broken.  We check later on if they are.
os_updates_broken=false

# We use dead-simple tests to infer OS type
if [ -f /etc/apt/sources.list ]; then os_type=debian
elif [ -f /etc/yum.conf ]; then os_type=redhat
fi

# For Debian variants (including Ubuntu), we key off the distro code name in
#  sources.list.  This quickly allows us to discern Debian vs Ubuntu, in a 
#  uniform way, across even old versions of either distro, and without counting
#  on the unreliable presence and format of /etc/lsb-release.
#
# Since we know that both Debian and Ubuntu give us a reliable way to discern
#  bugfix updates from security updates, we use that, and we set errata_support
#  to true across the board.
function discern_debvers() {
  # Here's where we pull our codename.  Every APT-based OS should have an
  #  'updates main' repo to pull a distro code name from.
  repostring="$(egrep "^deb " /etc/apt/sources.list | grep "updates main")"
  # Debian & Ubuntu post security updates in a reliable way
  errata_support=true

  # Set variables based on distro code name.  Ideally we'd be smarter about
  #  determining whether a given distro code name is EOL based on the current date
  #  and a list of EOL dates, but no time for that on version 1 of this checker.
  case "$repostring" in
    *squeeze*)
      distro=debian
      distrovers=6
      EOL=true
      ;;
    *wheezy*)
      distro=debian
      distrovers=7
      EOL=true
      ;;
    *jessie*)
      distro=debian
      distrovers=8
      EOL=true
      ;;
    *stretch*)
      distro=debian
      distrovers=9
      EOL=false
      ;;
    *buster*)
      distro=debian
      distrovers=10
      EOL=false
      ;;
    *lucid*)
      distro=ubuntu
      distrovers=10
      EOL=true
      ;;
    *precise*)
      distro=ubuntu
      distrovers=12
      EOL=true
      ;;
    *trusty*)
      distro=ubuntu
      distrovers=14
      EOL=true
      ;;
    *xenial*)
      distro=ubuntu
      distrovers=16
      EOL=true
      ;;
    *bionic*)
      distro=ubuntu
      distrovers=18
      EOL=false
      ;;
    *focal*)
      distro=ubuntu
      distrovers=20
      EOL=false
      ;;
    *groovy*)
      distro=ubuntu
      distrovers=20.10
      EOL=false
      ;;
    *hirsute*)
      distro=ubuntu
      distrovers=21.04
      EOL=false
      ;;
    *)
      exit 3
  esac
}

# This is where we poll status on outstanding updates.
# We clean the APT cache, then force it to refresh.  By forcing APT cache 
#  refresh, we ensure we have the most current status for updates, and we catch
#  any hosts that have broken APT - a common cause for silent patch logjams.
function debian_check_updates() {
  apt-get clean
  apt-get -qq update || os_updates_broken=true
  if [ -f "/usr/lib/update-notifier/apt-check" ]; then
    updatedata="$(/usr/lib/update-notifier/apt-check 2>&1)"
    security_updates="$(echo $updatedata | cut -d";" -f2)"
    all_updates="$(echo $updatedata | cut -d";" -f1)"
  else
    security_updates="$(apt-get upgrade -s | egrep '^Inst ' | grep -i security | wc -l)"
    all_updates="$(apt-get upgrade -s | egrep '^Inst ' | wc -l)"
  fi
}

function discern_redhatvers() {
  redhat_release="$(cat /etc/redhat-release)"
  case "$redhat_release" in
    *"Red Hat Enterprise Linux"*)
      distro=rhel
      case "$redhat_release" in
        *"Tikanga"*)
          distrovers=5
          EOL=true
          ;;
        *"Santiago"*)
          distrovers=6
          EOL=true
          ;;
        *"Maipo"*)
          distrovers=7
          EOL=false
          ;;
        *"Ootpa"*)
          distrovers=8
          EOL=false
          ;;
      esac
      ;;
    *"CentOS"*)
      distro=centos
      case "$redhat_release" in
        *"release 5"*)
          distrovers=5
          EOL=true
          ;;
        *"release 6"*)
          distrovers=6
          EOL=true
          ;;
        *"release 7"*)
          distrovers=7
          EOL=false
          ;;
        *"release 8"*)
          distrovers=8
          EOL=false
          ;;
      esac
      ;;
  esac
}

function redhat_check_updates() {
  security_updates="$(yum -q updateinfo list security | wc -l)"
  all_updates="$(yum check-update -q | wc -l)"
}

function centos_check_updates() {
  security_updates="-1"
  all_updates="$(yum check-update -q | wc -l)"
}

case $os_type in
  debian)
    discern_debvers
    if $EOL; then
      security_updates="-1"
      all_updates="-1"
    else
      debian_check_updates
    fi
    ;;
  redhat)
    discern_redhatvers
    if $EOL; then
      security_updates="-1"
      all_updates="-1"
    else
      if [ "$distro" == "redhat" ]; then
        redhat_check_updates
      else
        centos_check_updates
      fi
    fi
    ;;
  *)
    exit 2
    ;;
esac

JSON_FMT='{"eol":"%s","errata_support":"%s","security_updates":"%s", "all_updates": "%s", "os_updates_broken": "%s", "date_collected": "%s"}\n'

printf "$JSON_FMT" "$EOL" "$errata_support" "$security_updates" "$all_updates" "$os_updates_broken" "$date_collected"

