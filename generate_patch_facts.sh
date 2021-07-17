#!/bin/bash
#
# Collect OS-reported software patch details, format them into JSON, and store
#   them as an Ansible fact.
#
# Supports the following Linux variants and major versions:
#  - Debian 6 -> 10
#  - Ubuntu LTS 10 -> 20
#  - Ubuntu STS 20.10, 21.04
#
#  - CentOS 5 -> 8
#  - RHEL 5 -> 8
#  - Rocky Linux 8
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
# Updated 2021-06: Add extra capability for Rocky Linux.

# Don't let this script run w/o the ability to do things like update the package
#  cache.  And don't accidentally blow out /var/cache with non-root duplicates
#  of YUM caches.
running_as="$(whoami)" #Turns out we can't trust $USER to always be set :/
if [[ "$running_as" != "root" ]]; then
  echo "this script requires rootly powers"
  exit 2
fi

# Store output as Ansible fact?
store_ansible_fact=true

# Ansible fact name
factname=os_patch_status

# Ansible facts path; where we store our JSON output.
ansible_factspath=/etc/ansible/facts.d

# Simple ISO-8601 date
date_collected="$(date -I'minutes')"

# Determine uptime days in a pure-bash and multi-distro way, by performing integer
#  arithmetic based on uptime seconds as reported from /proc/uptime. Bash can't do floating
#  point math and we don't want to depend on something like `bc`.
# Because we have to use integers, and we don't want this to become complicated, uptimes from
#  0 seconds to 23 hours and 59 minutes will be '0 days up', and from thereon will be the whole
#  number of days up.
uptime_seconds="$(awk -F'.' '{print $1}' /proc/uptime)"
uptime_days="$(( $uptime_seconds / 60 / 60 / 24))"

# By default, assume OS updates are not broken.  We check later on if they are.
os_updates_broken=false

# By default, set needs_reboot to unknown
needs_reboot=unknown

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
  # This sorta sucks but it's quick and dirty compensation for the change in repo strings for archive repos.
  #   eg: `deb http://archive.debian.org/debian squeeze main`
  if [ -z "$repostring" ]; then
    repostring="$(egrep 'squeeze|wheezy|jessie|stretch|buster|lucid|precise|trusty|xenial|focal' /etc/apt/sources.list)"
  fi
  # Debian & Ubuntu post security updates in a reliable way
  errata_support=true

  # Set variables based on distro code name.  Ideally we'd be smarter about
  #  determining whether a given distro code name is EOL based on the current date
  #  and a list of EOL dates, but no time for that on version 1 of this checker.
  case "$repostring" in
    *squeeze*)
      distro=debian distrovers=6 EOL=true
      ;;
    *wheezy*)
      distro=debian distrovers=7 EOL=true
      ;;
    *jessie*)
      distro=debian distrovers=8 EOL=true
      ;;
    *stretch*)
      distro=debian distrovers=9 EOL=false
      ;;
    *buster*)
      distro=debian distrovers=10 EOL=false
      ;;
    *lucid*)
      distro=ubuntu distrovers=10 EOL=true
      ;;
    *precise*)
      distro=ubuntu distrovers=12 EOL=true
      ;;
    *trusty*)
      distro=ubuntu distrovers=14 EOL=true
      ;;
    *xenial*)
      distro=ubuntu distrovers=16 EOL=true
      ;;
    *bionic*)
      distro=ubuntu distrovers=18 EOL=false
      ;;
    *focal*)
      distro=ubuntu distrovers=20 EOL=false
      ;;
    *groovy*)
      distro=ubuntu distrovers=20.10 EOL=false
      ;;
    *hirsute*)
      distro=ubuntu distrovers=21.04 EOL=false
      ;;
    *)
      exit 3
  esac
}

# For Red Hat variants, we key off of redhat-release which has been predictable
#   going back at least to RHEL/CentOS 5, which is as far back as we care about.
#
# When the distro is RHEL, we know we have reliable errata support, but when
#   CentOS, we know that we don't have errata support aside from EPEL, so we
#   mark errata_support as false to denote that we can't distinguish security
#   updates from normal bugfix package updates.  This sucks, thanks Red Hat.
#   Same deal for Rocky Linux, which also fails to distinguish bugfix from
#   security. (see `dnf check-update --security`)

function discern_redhatvers() {
  redhat_release="$(cat /etc/redhat-release)"
  case "$redhat_release" in
    *"Red Hat Enterprise Linux"*)
      distro=rhel
      errata_support=true
      case "$redhat_release" in
        *"Tikanga"*)
          distrovers=5 EOL=true
          ;;
        *"Santiago"*)
          distrovers=6 EOL=true
          ;;
        *"Maipo"*)
          distrovers=7 EOL=false
          ;;
        *"Ootpa"*)
          distrovers=8 EOL=false
          ;;
      esac
      ;;
    *"CentOS"*)
      distro=centos
      errata_support=false
      case "$redhat_release" in
        *"release 5"*)
          distrovers=5 EOL=true
          ;;
        *"release 6"*)
          distrovers=6 EOL=true
          ;;
        *"release 7"*)
          distrovers=7 EOL=false
          ;;
        *"release 8"*)
          distrovers=8 EOL=false
          ;;
      esac
      ;;
    *"Rocky Linux"*)
      distro=rocky
      errata_support=false
      case "$redhat_release" in
        *"release 8"*)
        distrovers=8 EOL=false
        ;;
      esac
      ;;
  esac
}


# This is where we poll status on outstanding updates.
# We clean the APT cache, then force it to refresh.  By forcing APT cache 
#  refresh, we ensure we have the most current status for updates, and we catch
#  any hosts that have broken APT - a common cause for silent patch logjams.
function debian_check_updates() {
  apt-get clean
  apt-get -qq update 2>/dev/null || os_updates_broken=true
  if [ -f "/usr/lib/update-notifier/apt-check" ]; then
    updatedata="$(/usr/lib/update-notifier/apt-check 2>&1)"
    security_updates="$(echo $updatedata | cut -d";" -f2)"
    all_updates="$(echo $updatedata | cut -d";" -f1)"
  else
    security_updates="$(apt-get upgrade -s | egrep '^Inst ' | grep -i security | wc -l)"
    all_updates="$(apt-get upgrade -s | egrep '^Inst ' | wc -l)"
  fi
}

function redhat_check_updates() {
  security_updates="$(yum -q updateinfo list security | wc -l)"
  all_updates="$(yum check-update -q | wc -l)"
}

# CentOS doesn't publish security errata, so we can't use `list security`.
# Instead we just toss out `-1` to make it easy to discern that this is a bogus value.
function centos_check_updates() {
  security_updates="-1"
  all_updates="$(yum check-update -q | wc -l)"
}

function ensure_ansible_factspath() {
  if [[ ! -d $ansible_factspath ]]; then
    mkdir -p $ansible_factspath
  fi
}

# Here's where we try to determine if a system needs to be rebooted in order
#   to load patched versions of the kernel, services, or libraries.

function needs_reboot() {
  case $os_type in
    # For Debian variants, this is easy and uniform across all common versions
    #   of Debian and Ubuntu.
    debian)
      if [ -f /var/run/reboot-required ]; then
        needs_reboot=true
      else
        needs_reboot=false
      fi
    ;;
    redhat)
      case "$redhat_release" in
        # For redhat variants this old, we can't easily determine if a system
        #   needs to be rebooted to apply packages, and in 2021 we should just
        #   throw the whole computer away if it's still running el5.
        *"release 5"*)
          needs_reboot=unknown
          ;;
        # The needs-restarting binary is part of yum-utils, which is an optional
        #   package that we can't trust is installed.
        # Further, for el6, we don't get a determinative RC from running this 
        #   command, so we have to check for output, which only happens when
        #   a system has procs that need to be reloaded.
        *"release 6"*)
          if [ -f "/usr/bin/needs-restarting" ]; then
            restartable_procs=$(/usr/bin/needs-restarting | wc -l)
            if (( $restartable_procs > 0 )); then
              needs_reboot=true
            else
              needs_reboot=false
            fi
          fi
          ;;
        # This is the catch-all with the understanding that if it's not el5 nor el6
        #   that it'll be el7+, which is a new enough version of yum-utils to use a
        #   determinative RC - 0: all good, 1: needs restarting.
        *)
          if [ -f "/usr/bin/needs-restarting" ]; then
            if /usr/bin/needs-restarting -r 1>/dev/null; then
              needs_reboot=false
            else
              needs_reboot=true
            fi
          else
            needs_reboot=unknown
          fi

          ;;
      esac
    ;;
  esac
}


# Set all vars aside from needs_reboot
case $os_type in
  debian)
    discern_debvers
    debian_check_updates
    ;;
  redhat)
    discern_redhatvers
      if [ "$distro" == "redhat" ]; then
        redhat_check_updates
      else
        centos_check_updates
      fi
    ;;
  *)
    exit 2
    ;;
esac

# Set needs_reboot variable
needs_reboot

# Write those facts out!
if $store_ansible_fact; then
  ensure_ansible_factspath
  JSON_FMT='{"eol":"%s","errata_support":"%s","security_updates":"%s", "all_updates": "%s", "os_updates_broken": "%s", "needs_reboot": "%s", "uptime_days": "%s", "date_collected": "%s"}\n'
  printf "$JSON_FMT" "$EOL" "$errata_support" "$security_updates" "$all_updates" "$os_updates_broken" "$needs_reboot" "$uptime_days" "$date_collected" > $ansible_factspath/$factname.fact
fi
