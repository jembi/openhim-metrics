# Puppet manifest
#
# Required modules:
# willdurand/nodejs
# puppetlabs/mongodb
#

# Change source_dir if necessary
$source_dir="../../../."

# defaults for Exec
Exec {
	path => ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/local/node/node-default/bin/"],
	user => "root",
}

class { '::mongodb::globals':
	manage_package_repo => true
}

class { "mongodb":
	init => "upstart",
}

class { "nodejs":
	version => "stable",
}

exec { "npm-install":

	command => "npm install",
	require => Class["nodejs"],
}

exec { "coffeescript":
	command => "npm install -g coffee-script",
	require => Class["nodejs"],
}

exec { "mocha":
	command => "npm install -g mocha",
	require => Class["nodejs"],
}
