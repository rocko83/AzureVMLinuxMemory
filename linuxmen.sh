#!/bin/bash
export CONFFILE=.config
function MKTMPFILE() {
	case $1 in
	create)
		mktemp -p /tmp --suffix -linuxsshmen
		;;
	delete)
		rm -f $2
		;;
	*)
		echo erro
		exit 1
		;;
	esac
}
function GETRAM(){
  export DBFILE=$(READCONF DBFILE)
  export TMPDATA=$(MKTMPFILE create)
  export TMPDATA2=$(MKTMPFILE create)
  sqlite3 -separator " " $DBFILE "select vmip, vmname, vmid from  vms where lastdata == 0" > $TMPDATA2
  echo COLLECTING RAM USAGE
  export TOTAL=$(wc -l $TMPDATA2 | awk '{print $1}')
  export COUNTER=1
  while read vmip vmname vmid
  do
    #echo -ne "$COUNTER/$TOTAL\r"
    echo $COUNTER/$TOTAL
    echo $vmname $vmip
    SSHREMOTOIKEYLESS $vmip "cat /proc/meminfo" > $TMPDATA
    export RETURN=$?
    if [ $RETURN -ne 0 ]
    then
      echo FAil to connect to $vmname $vmip
      sqlite3 $DBFILE "update vms set lascheckstatus=1 ,lastdata='$TIMESTAMP'  where vmid = '$vmid'"
    else
      export MENTOTAL=$(cat $TMPDATA | egrep -w "^MemTotal" | awk '{print $2}')
      export MENAVAIL=$(cat $TMPDATA | egrep -w "^MemAvailable" | awk '{print $2}')
      export MEMUSED=$(expr $MENTOTAL - $MENAVAIL)
      RAMPER=$(printf "%.3f" $(echo "($MEMUSED * 100 ) /  $MENTOTAL "| bc -l| sed -e "s/\./,/g"))
      TIMESTAMP=$(date +"%s")
      echo Success, $vmname $vmip Ram Percent = $RAMPER
      sqlite3 $DBFILE "update vms set ramper='$RAMPER',lastdata='$TIMESTAMP'  where vmid = '$vmid'"
    fi
    COUNTER=$(expr $COUNTER + 1)
  done < $TMPDATA2
  #expr $(expr $(expr $MEMUSED \* 100) \/ $MENTOTAL)

  MKTMPFILE delete $TMPDATA
  MKTMPFILE delete $TMPDATA2
}
function GETCPU(){
  echo null
}
function COLLECT(){
  DBINIT
  GETVMLIST
  GETIP
  #GETRAM
  #export RAMPER=$(GETRAM 1.2.3.4)
  #echo $RAMPER
}
function GETSIZE(){
  echo null
}
function GETVMLIST(){
  echo COLLECTING VMLIST ADDRESS
  export DBFILE=$(READCONF DBFILE)
  export TMPDATA=$(MKTMPFILE create)
  az vm list  --query "[].[name,id,hardwareProfile.vmSize,resourceGroup,location,networkProfile.networkInterfaces[0].id]" -o tsv > $TMPDATA
  export TOTAL=$(wc -l $TMPDATA | awk '{print $1}')
  echo $TOTAL VMs Found on azure
  export COUNTER=1
  echo Updating database
  while read VMNAME VMID VMSIZE VMRG LOCATION NICID
  do
    #export VMIP=$(GETIP $NICID $VMNAME $VMRG)


    #echo $VMNAME $LOCATION $VMRG
    echo -ne "$COUNTER/$TOTAL\r"
    sqlite3 $DBFILE "INSERT INTO vms(vmname,vmid,vmsize,vmrg,location,nicid,vmip,ramper,lastdata,lascheckstatus) SELECT '$VMNAME', '$VMID','$VMSIZE','$VMRG','$LOCATION','$NICID','null','null','0','1' WHERE NOT EXISTS(SELECT 1 FROM vms WHERE vmid = '$VMID')"
    COUNTER=$(expr $COUNTER + 1)
  done < $TMPDATA
  MKTMPFILE delete $TMPDATA
}
function GETIP() {
  echo COLLECTING IP ADDRESS
  export DBFILE=$(READCONF DBFILE)
  export TMPDATA=$(MKTMPFILE create)
  sqlite3 -separator " " $DBFILE "select vmname, nicid, vmrg from  vms where vmip == 'null'" > $TMPDATA
  export TOTAL=$(wc -l $TMPDATA  | awk '{print $1}')
  export COUNTER=1
  while read VMANAME NICID VMRG
  do
    #echo $COUNTER \/ $TOTAL $VMANAME $VMRG
    echo -ne "$COUNTER/$TOTAL\r"
    export VMIP=$(az vm nic show --nic "$NICID" --vm-name $VMANAME --resource-group $VMRG --query "[ipConfigurations[0].privateIpAddress]" -o tsv)
    sqlite3 $DBFILE "update vms set vmip='$VMIP' where nicid = '$NICID'"
    COUNTER=$(expr $COUNTER + 1)
  done < $TMPDATA
  MKTMPFILE delete $TMPDATA
}
function DBINIT()
{
  export DBFILE=$(READCONF DBFILE)
  sqlite3 $DBFILE "create table IF NOT EXISTS vms(vmname varchar(255) , vmid varchar(300) primary key,vmsize varchar(50), vmrg varchar(50), location varchar(50), nicid varchar(300), vmip varchar(15), ramper varchar(6), lastdata real, lascheckstatus int  )"

}
function COPYKEY(){
  export SSHPASS=$(READCONF PASSWORD)
  export USER=$(READCONF USER)
  sshpass -e ssh-copy-id ${USER}@$1
}
function SSHREMOTOIWTHKEY(){
  export USER=$(READCONF USER)
  export KEYFILE=$(READCONF KEYFILE)
  ssh -i $KEYFILE -o ConnectTimeout=3 ${USER}@$1 "$2"
}
function SSHREMOTOIKEYLESS(){
  export SSHPASS=$(READCONF PASSWORD)
  export USER=$(READCONF USER)
  sshpass -e ssh -o ConnectTimeout=3 ${USER}@$1 "$2"
}
function CRUDE(){
  #CREATE
  #UPDATE
  #DELETE
  echo null
}
function READCONF(){
  if [ -f $CONFFILE ]
  then
    cat $CONFFILE | grep -v ^\# |grep -w ^$1 | awk -F = '{print $2}'
  else
    echo Error, config file does not exist.
    echo Please, create one.
    exit 1
  fi

}
function GENERATECONF(){
  if [ -f $CONFFILE ]
  then
    echo Config already existe.
    echo Do you want to replace ?
    echo YES/NO
    read RETURN
    if [ $(echo $RETURN | head -c 1 | tr 'A-Z' 'a-z')  != y ]
    then
      exit 0
    else
      cat << EOF > $CONFFILE
USER=
PASSWORD=
KEYFILE=
DBFILE=
EOF
      if [ -f $CONFFILE ]
      then
        echo $CONFFILE created sucessful
      else
        echo $CONFFILE was not crete check permissions and everything else.
      fi
    fi
  else
    cat << EOF > $CONFFILE
USER=
PASSWORD=
KEYFILE=
DBFILE=
EOF
    if [ -f $CONFFILE ]
    then
      echo $CONFFILE crete sucessful
    else
      echo $CONFFILE was not crete check permissions and everything else.
    fi
  fi

}
function HELP(){
  echo Linux Azure performance statistic
  echo USAGE:
  echo $0 getram \<hostname\>
  echo $0 getcpu
  echo $0 copykey \<hostname\>
  echo $0 generateconf
  exit 1
}
if [ $# -eq 1 ]
then
  case $1 in
    collect)
      COLLECT
      ;;
    generateconf)
      GENERATECONF
      ;;
    getram)
      GETRAM
      ;;
    *)
      HELP
      ;;
  esac
else
  if [ $# -eq 2 ]
  then
    case $1 in
      copykey)
        echo null
        ;;
      teste)
        echo null
        ;;
      *)
        HELP
        ;;
    esac
  else
    HELP
  fi
fi
