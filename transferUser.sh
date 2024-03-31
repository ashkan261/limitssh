#!/bin/bash

# Variables
server1_ip="144.202.48.39"
server1_port="443"
server1_user="root"
server1_pass="WrtcqtjUeuhb663i"

server2_ip="170.64.234.4"
server2_port="443"
server2_user="root"
server2_pass="WrtcqtjUeuhb663i"

backup_users_command="awk -F: '$3 >= 1000 { print \$0 }' /etc/passwd > /var/backups/users_backup.txt && cp /etc/shadow /var/backups/shadow.backup"
restore_users_command="sudo newusers /var/backups/users_backup.txt && sudo cp /var/backups/shadow.backup /etc/shadow && sudo chmod 600 /etc/shadow"

# Functions
check_and_install_sshpass() {
    local ip=$1
    local port=$2
    local user=$3
    local pass=$4

    if ! ssh "$user@$ip" -p "$port" 'which sshpass' &>/dev/null; then
        echo "sshpass is not installed on $ip, installing..."
        sshpass -p "$pass" ssh "$user@$ip" -p "$port" 'sudo apt-get update && sudo apt-get install -y sshpass'
    else
        echo "sshpass is already installed on $ip"
    fi
}

backup_users() {
    local ip=$1
    local port=$2
    local user=$3
    local pass=$4

    echo "Backing up users on $ip"
    sshpass -p "$pass" ssh "$user@$ip" -p "$port" "$backup_users_command"
}

transfer_backup() {
    local source_ip=$1
    local source_port=$2
    local source_user=$3
    local source_pass=$4
    local dest_ip=$5
    local dest_user=$6

    echo "Transferring backup from $source_ip to $dest_ip"
    sshpass -p "$source_pass" scp -P "$source_port" "$source_user@$source_ip:/var/backups/*" "$dest_user@$dest_ip:/var/backups/"
}

restore_users() {
    local ip=$1
    local port=$2
    local user=$3
    local pass=$4

    echo "Restoring users on $ip"
    sshpass -p "$pass" ssh "$user@$ip" -p "$port" "$restore_users_command"
}

check_and_create_directory() {
    local ip=$1
    local port=$2
    local user=$3
    local pass=$4
    local directory=$5

    sshpass -p "$pass" ssh "$user@$ip" -p "$port" "if [ ! -d $directory ]; then sudo mkdir -p $directory; fi"
}

transfer_file() {
    local source_ip=$1
    local source_port=$2
    local source_user=$3
    local source_pass=$4
    local dest_ip=$5
    local dest_user=$6
    local file=$7

    sshpass -p "$source_pass" scp -P "$source_port" "$source_user@$source_ip:$file" "$dest_user@$dest_ip:$file"
}

# Main script
check_and_install_sshpass "$server1_ip" "$server1_port" "$server1_user" "$server1_pass"
check_and_install_sshpass "$server2_ip" "$server2_port" "$server2_user" "$server2_pass"

backup_users "$server1_ip" "$server1_port" "$server1_user" "$server1_pass"

transfer_backup "$server1_ip" "$server1_port" "$server1_user" "$server1_pass" "$server2_ip" "$server2_user"

restore_users "$server2_ip" "$server2_port" "$server2_user" "$server2_pass"

check_and_create_directory "$server2_ip" "$server2_port" "$server2_user" "$server2_pass" "/home/ubuntu/"

files=("/root/out.json" "/root/traffic.json" "/home/ubuntu/out.json" "/home/ubuntu/traffic.json")

for file in "${files[@]}"; do
    if sshpass -p "$server1_pass" ssh "$server1_user@$server1_ip" -p "$server1_port" "[ -f $file ]"; then
        echo "$file exists on $server1_ip"
        transfer_file "$server1_ip" "$server1_port" "$server1_user" "$server1_pass" "$server2_ip" "$server2_user" "$file"
    else
        echo "$file does not exist on $server1_ip"
    fi
done