#!/bin/sh
## Autor:Osoda
## backup one mysql db into a one file, also verify if is a db no valid, and endly compress the file in a tar
## - Now could be manage by another user distint to root

## Putting the script in /var/backups/mysql seems sensible... on a debian machine that is
## Create the group user and add in user to use, too directories
# mkdir -p /var/backups/mysql/databases/individual
# mkdir -p /var/backups/mysql/databases/bk
# mkdir -p /var/backups/mysql/databases/individual/public
# groupadd mysql-backup
# chown :mysql-backup dump_dbname2.sh
# chmod g+xr name_thisfile.sh
# chown :mysql-backup individual/public
# chmod g+rwx individual/public/
# usermod -a -G mysql-backup usuario

## Create 'backup' mysql user
## Permisos basicos para hacer un DUMP
# CREATE USER 'backup'@'localhost' IDENTIFIED BY '1';
## Permisos Globales para dumpear una db. A nivel Global
# GRANT RELOAD, SHOW DATABASES ON *.* TO 'backup'@'localhost';
## Permisos mas basicos para dumpear una db en concret. a nivel de DB para abajo
# GRANT EVENT,/*IniPrivTable*/SHOW VIEW,TRIGGER,INDEX,/*IniPrivColumn*/SELECT ON `backup`.* TO 'backup'@'localhost';
## Permisos mas basicos para dumpear los SP de una db en concreto. A nivel de SP
#GRANT SELECT ON mysql.proc TO 'backup'@'localhost';

#Obtiene la verdadera direccion de guardado, dependiendo del usurio
getDirSave(){
  _dirsave=$1
        _user="$(whoami | sed 's/[[:space:]]*$//')"
  if [[ $_user = 'root' ]]; then
    echo $_dirsave
  else
    _dirsave="$_dirsave/public/$_user"
    #Creamos la carpeta del usuario por si no existe
    mkdir -p $_dirsave/{bk,databases}
    [[ "$?" != 0 ]] && exit 1
    # Creamos un link para la carpeta del usuario externo
    lin="~/configs_dd/mysql_backcup"
    if [ ! -L $_lin ]; then
      ln -s $_dirsave/ ~/configs_dd/mysql_backcup
      [[ "$?" != 0 ]] && exit 1
    fi
    echo $_dirsave
  fi
}

USER="root"
#USER="backup"
#PASSWORD="1"
DIR=$(dirname $(readlink -f $0))
DIRSAVE=$DIR"/individual"
DIRSAVE=$(getDirSave $DIRSAVE)
[[ "$?" != 0 ]] && echo "ERROR General: No se puede crear las carpetas para los  bk." && exit 1
OUTPUTDIR=$DIRSAVE"/databases"
MYSQLDUMP="/usr/bin/mysqldump"
MYSQL="/usr/bin/mysql"

usage() { echo "$0 usage:" && grep " .)\ #" $0; exit 0; }
[ $# -eq 0 ] && usage
while getopts ":hd:u:" arg; do
  case $arg in
    d) # Nombre de la db a hacer una copia
      DB=${OPTARG}
      echo "- Mysql. Nombre DB: ${DB}"
      ;;
    u) #Usuario para conectarse a mysql
      USER=${OPTARG}
      echo "- Mysql. Usuario: $USER"
      if [ -n "$USER" ] ; then
        ### Input password as hidden charactors ###
        read -s -p "- Mysql. Digite la contrasena: "  PSWD
        MYSQL_USER=" --user=$USER --password=$PSWD "
      else
        echo "ERRROR: Debe definir el nombre del usuario mysql."
        exit 1
      fi
      ;;
    :)
      echo "ERROR: La opción -${OPTARG} requiere argumentos"
      exit 1
      ;;
    h | *) # Display help.
      usage
      exit 0
      ;;
  esac
done

#Consulta que excluye las DB de sytema y otras innecesarias
SHOW="SHOW DATABASES WHERE \`DATABASE\` NOT IN ( \
    'mysql','information_schema' \
  ) AND (\`DATABASE\` LIKE '"$DB"')"
FILE=$DIRSAVE"/bk/DB_"$DB$(date '+%Y%m%d%H%M.tar.gz')
ERROR_TMP=$(mktemp)
if [ -n "$DB" ]; then
  echo "- Mysql. Creando conexion y validando DBs"
  databases=`$MYSQL $MYSQL_USER --batch --skip-column-names -e "$SHOW"`
  [ -z "$databases" ] && echo "- ERORR: Mysql. La DB no fue encontrada en el servidor." && exit 1
  echo "- Mysql. DBs validadas: "$databases
  echo "- Borrando directorio de BK de dbs"
  rm -f $OUTPUTDIR/*
  echo "- Mysql. Inicio del DUMPEO de DBs"
  for database in $databases; do
    ERROR_MYSQL=`\
    $MYSQLDUMP \
    $MYSQL_USER \
    --force \
    --quote-names --dump-date \
    --opt --single-transaction \
    --events --routines --triggers \
    --databases $database \
    --result-file="$OUTPUTDIR/$database.sql" 2>&1`
    [[ "$?" != 0 || -n "$ERROR_MYSQL" ]] && echo "ERROR Mysql: "$ERROR_MYSQL$'\n'"ERROR General: No se puedo generar el DUMPEO de la db original." && exit 1

  done
else
  echo '- Errror: nombre de db vacia'
  exit 1
fi


echo '- Comprimiendo el backup '
tar -czvf $FILE -C $DIRSAVE"/" "databases/"
echo '- Guardado en: '$FILE
