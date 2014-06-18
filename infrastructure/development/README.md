openHIM Metrics Service
============================

Development Instance
--------------------
Vagrant/Puppet can be used to setup a development instance of the drug-stock-service. Simply run ```vagrant up``` from within the ```env/``` directory.

Stand-alone Puppet
------------------
Alternatively there's a stand-alone puppet script available ```env/metrics-dev-standalone.pp```:

* Ensure that puppet is installed and setup with the following modules:
	* willdurand/nodejs
	* puppetlabs/mongodb

* Run puppet:
	```
	cd env
	sudo puppet apply metrics-dev-standalone.pp
	```

The standalone script doesn't export the NODE_ENV environment variable (yet), so before running node it's best to run the command
```
export NODE_ENV=development
```
