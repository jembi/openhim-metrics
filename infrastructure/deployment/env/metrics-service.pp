# Puppet manifest
#
# Required modules:
# willdurand/nodejs
# puppetlabs/mongodb
#

# Set home and change source_dir to the drug-stock-service source location
$home="/home/jembi"
$source_dir="${home}/drug-stock-service"
$node_env="production"

# defaults for Exec
Exec {
	path => ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/local/node/node-default/bin/"],
	user => "root",
}

class { 'mongodb::globals':
	manage_package_repo => true
}

class { "mongodb":
	init => "upstart",
}

class { "nodejs":
	version => "stable",
}

exec { "npm-install":
	cwd => "$source_dir",
	command => "npm install",
	require => Class["nodejs"],
}

exec { "coffeescript":
	command => "npm install -g coffee-script",
	require => Class["nodejs"],
}

exec { "build":
	cwd => "$source_dir",
	command => "cake build",
	require => Class["coffeescript"],
}

file { "/etc/init/drug-stock-service.conf":
	ensure  => file,
	content => template("$source_dir/infrastructure/deployment/env/upstart.erb"),
}

exec { "start-service":
	command => "start drug-stock-service",
	require => [ Exec["npm-install"], Exec["build"], File["/etc/init/drug-stock-service.conf"] ]
}

file { "${home}/deploy.sh":
	ensure  => file,
	source => "${source_dir}/infrastructure/deployment/deploy/deploy.sh",
}
