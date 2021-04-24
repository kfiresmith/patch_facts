# patch_facts
Generate OS patch facts for Ansible

## General Function and Operation
The script `generate_patch_facts.sh` provides a single line of output to `/etc/ansible/facts.d/os_patch_status.fact`.
This script should be run via cron, so that the content is present on the system at time of fact gathering, rather
than be used as an executable fact, since querying the OS for patch status can take 2-10s.


