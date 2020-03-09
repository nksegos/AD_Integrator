# AD Integrator
Built and tested on vanilla debian installations, but the script should work on any derivative distro as well. The script is intended to be used for mass deployments of freshly installed identical systems, but surely can be used individually with some changes on the code(maybe an override parameter could be added in the future). 

The hostname naming scheme is as follows: 
**${USER_DEFINED_PREFIX}-${LAST_PART_OF_THE_HOST_IP_ADDRESS}.**

**e.g.** A host with the IPv4 address set as 10.1.1.25 and the prefix defined as 'lpc' would be configured as : **lpc-25**

## Operation
The script can be executed in the following ways:

* **Interactively**: No flags are used and the user provides input when and where needed. Mainly useful for debugging.
* **Load parameters from a config file**: The integration parameters are loaded from a user specified file written in the "NAME=VALUE" format, with the option to make no user prompts and execute automatically.
* **Load parameters as flag options**: The user provides the parameters as arguments to the scripts prior to the execution. **NOTE**: The password must be provided in a file if that execution mode is chosen.
* **Set the necessary variables within the script**: Even though all the necessary variables can be set in the first 10 lines...No. Just don't.

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
