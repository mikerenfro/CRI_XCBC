Powershell scripts to integrate OpenHPC into an existing computer lab environment, for institutions who want to leverage traditional Windows computer labs for additional capacity in an OpenHPC installation.

Requirements:

- Open-minded lab and network administrators
- DHCP option classes supporting iPXE on authoritative DHCP servers

Includes:

- Powershell script to create accurate node inventories from selected lab computers
- Powershell script to reboot selected lab computers from Windows into OpenHPC and back. Windows to OpenHPC process includes converting DHCP lease into reservation, modifying reservation to boot OpenHPC, and rebooting. OpenHPC to Windows process includes removing reservation and requires triggering a reboot from the OpenHPC head node.