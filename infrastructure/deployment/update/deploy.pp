#manifest for deploying the latest metrics-service from GitHub

# Change source_dir to the metrics-service source location
$source_dir="/home/jembi/metrics-service"

# defaults for Exec
Exec {
        path => ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/local/node/node-default/bin/"],
        user => "root",
}

exec { "npm-install":
        cwd => "$source_dir",
        command => "npm install",
}

exec { "build":
        cwd => "$source_dir",
        command => "cake build",
        require => Exec["npm-install"],
}

exec { "stop-service":
        command => "metrics-service",
        require => Exec["build"]
}

exec { "start-service":
        command => "start metrics-service",
        require => Exec["stop-service"]
}}
