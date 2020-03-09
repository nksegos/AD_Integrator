# AD Integrator
Built and tested on vanilla debian installations, but the script should work on any derivative distro as well. The script

## integrator.sh
```
$ ./integrator.sh -h
Usage:
 		-d DOMAIN: Provide the domain to be joined.
 		-c DOMAIN_CONTROLLER: Provide the hostname of the domain controller.
 		-b BASE_HOSTNAME: Provide the base hostname prefix for the joined machine.
 		-u DOMAIN_BIND_USER: Provide the user to join the domain with.(Default: Administrator)
 		-p PASSWORD_FILE: Provide the password file for the user to join the domain.
 		-f CONFIG_FILE: Load integration pararameters from a config file.
 		-g: Generate a blank config file.
 		-a: Set execution mode to automatic. User won't be queried for host reboot or to setting restoration in case of failure.
 		-h: Display help menu.
```
