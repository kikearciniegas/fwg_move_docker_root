#!/bin/bash

##
# script to make docker containers' configuration persist between reboots of the firewalla box
# the script must be created at /home/pi/.firewalla/config/post_main.d/start_[service-name].sh

##
# as per our own configuration, the docker root has been moved to the ssd drive
# so, after every reboot, we must check whether or not, the drive is mounted
# and the /var/lib/docker directory has been copied to the new docker root path
# before starting the docker containers

##
# args
TMPDIR='/tmp'
MNTDIR='/mnt/data'
CHCK_FILE='/.do_not_remove_this_file'
LOG_FILE='/tmp/docker_move.log'
JSN_FILE='/etc/docker/daemon.json'
ODCKRROOT='/var/lib/docker'
NDCKRROOT="$MNTDIR/var/lib/docker"
DCKRCNTNT="$ODCKRROOT/overlay2"
USRNAME='pi'
DCKRGROUP='docker'

##
# start the script
printf "%s\n" "script has started..."

##
# start move docker root to ssd hdd
# 1. check for access to mount point
# 2. stop all docker containers and purge the system
# 3. update the daemon.json file with the new root path
# 4. copy the old /var/lib/docker directory into the new root path
# 5. add the user to the docker group
# 6. start the docker daemon
# 5. end
#

printf "%b\n" "\nchecking $NDCKRROOT..."
if [[ $(docker info | grep $NDCKRROOT) ]] && [ -d $NDCKRROOT ]; then
  printf "%s\n" " - docker root is already pointing to $NDCKRROOT... ok"
  printf "%s\n" " - $NDCKRROOT is accessible... ok"
  if grep -Fq "${NDCKRROOT}" "${JSN_FILE}"; then
    printf "%s\n" " - $NDCKRROOT already exists in the $JSN_FILE file... ok"
  else
    printf "%b\n" "\nsome work needed..."
    # check for the ssd hdd mount point
    #
    printf "%b\n" "\naccessing $MNTDIR$CHCK_FILE..."
    if [[ -f $MNTDIR$CHCK_FILE ]]; then
      printf "%s\n" " - $MNTDIR$CHCK_FILE is accessible... ok"
    else
      printf "%s\n" " * - couldn't access $MNTDIR$CHCK_FILE... something is wrong"
      printf "%b\n" "$(date +%F) - couldn't access $MNTDIR$CHCK_FILE... something is wrong" >> $LOG_FILE
      printf "%s\n" " - let's run the ssd hdd mounting script anyways..."
      ./mount_sata_drive.sh
      sleep 5
      if [[ -f $MNTDIR$CHCK_FILE ]]; then
        printf "%s\n" " - $MNTDIR$CHCK_FILE is accessible... ok"
      else
        printf "%s\n" " * - couldn't access $MNTDIR$CHCK_FILE... something is wrong"
        printf "%b\n" "$(date +%F) - couldn't access $MNTDIR$CHCK_FILE... something is wrong" >> $LOG_FILE
        exit 1
      fi
    fi

    cd $TMPDIR
    printf "%s\n" " - moved to $(pwd)"

    # stop all docker containers and the docker daemon to purge the system
    #
    printf "%b\n" "\nstopping containers and the docker daemon..."
    sudo systemctl stop docker-compose@*
    sleep 5
    printf "%s\n" " - docker purge started..."
    sudo docker system prune -a -f --volumes
    sudo systemctl stop docker
    sleep 5
    sudo rm -rf $DCKRCNTNT/*
    printf "%s\n" " - docker has been stopped and containers, images and volumes purged... ok"

    # update the /etc/docker/daemon.json file with the new root path
    #
    printf "%b\n" "\ninserting root path into the $JSN_FILE file..."
    sudo systemctl stop docker-compose@*
    sleep 5
    sudo docker system prune -a -f --volumes
    sudo systemctl stop docker
    sleep 5
    if [[ -f $JSN_FILE ]]; then sudo rm -rf $JSN_FILE; fi
    sudo touch $JSN_FILE
    #sudo su -c "$(printf "%b\n" "{\n\"data-root\": \"$NDCKRROOT\"\n}" > $JSN_FILE)"
    sudo su -c "echo -e '{\n\"data-root\": \"$NDCKRROOT\"\n}' > $JSN_FILE"
    if grep -Fq "${NDCKRROOT}" "${JSN_FILE}"; then
      printf "%s\n" " - docker is stopped and the new docker root has been inserted into the $JSN_FILE file... ok"
    else
      printf "%s\n" " * - couldn't write $JSN_FILE file... something is wrong"
      printf "%b\n" "$(date +%F) - couldn't write $JSN_FILE file... something is wrong" >> $LOG_FILE
      exit 1
    fi

    # copy the old docker directory into the new root path
    #
    printf "%b\n" "\ncopying old docker directories $ODCKRROOT into new root path $NDCKRROOT..."
    sudo systemctl stop docker-compose@*
    sleep 5
    sudo docker system prune -a -f --volumes
    sudo systemctl stop docker
    sleep 5
    if [[ -d $NDCKRROOT ]]; then sudo rm -rf $NDCKRROOT; fi
    sudo mkdir -p $NDCKRROOT && sudo chmod 711 $NDCKRROOT
    sudo cp -axT $ODCKRROOT $NDCKRROOT
    if [[ -d $NDCKRROOT ]]; then
      printf "%s\n" " - the new docker root $NDCKRROOT has been created, permissions applied and group ownership updated... ok"
    else
      printf "%s\n" " * - couldn't access $NDCKRROOT directory... something is wrong"
      printf "%b\n" "$(date +%F) - couldn't access $NDCKRROOT directory... something is wrong" >> $LOG_FILE
      exit 1
    fi

    # add user to the docker group
    #
    printf "%b\n" "\nadding user $USRNAME to $DCKRGROUP group..."
    if [ $(getent group $DCKRGROUP) ]; then
      printf "%s\n" " - the group $DCKRGROUP already exists... ok"
      sudo usermod -aG $DCKRGROUP $USRNAME
      printf "%s\n" " - user $USRNAME added to $DCKRGROUP group... ok"
    else
      sudo groupadd $DCKRGROUP && sudo usermod -aG $DCKRGROUP $USRNAME
      printf "%s\n" " - the group $DCKRGROUP has been created and user $USRNAME added to group... ok"
    fi

    # start the docker daemon
    #
    printf "%b\n" "\nstarting the docker daemon..."
    if (! sudo docker stats --no-stream ); then
      sudo systemctl start docker
      sleep 5
      #wait until docker daemon is running and has completed initialisation
      while (! sudo docker stats --no-stream ); do
        # docker takes a few seconds to initialize
        printf "%s\n" " - waiting for docker to launch..."
        sleep 5
      done
      sudo docker system prune -a -f --volumes
      printf "%s\n" " - docker daemon restarted... ok"
    else
      printf "%s\n" " - docker daemon is running... ok"
    fi
  fi
fi
# finished moving the docker root to the ssd hdd
printf "%b\n" "\nmove docker root script has ended..."
##
