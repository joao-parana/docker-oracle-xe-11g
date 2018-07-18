#!/bin/bash

echo "`date` - Veja abaixo o Environment disponível para o Entrypoint "
env
echo "`date` "
    
# SOMA_PASSWD=soma_123 deve vir via ARG no Dockerfile

# Prevent owner issues on mounted folders
chown -R oracle:dba /u01/app/oracle
rm -f /u01/app/oracle/product
ln -s /u01/app/oracle-product /u01/app/oracle/product
# Update hostname
sed -i -E "s/HOST = [^)]+/HOST = $HOSTNAME/g" /u01/app/oracle/product/11.2.0/xe/network/admin/listener.ora
sed -i -E "s/PORT = [^)]+/PORT = 1521/g" /u01/app/oracle/product/11.2.0/xe/network/admin/listener.ora
echo "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe" > /etc/profile.d/oracle-xe.sh
echo "export PATH=\$ORACLE_HOME/bin:\$PATH" >> /etc/profile.d/oracle-xe.sh
echo "export ORACLE_SID=XE" >> /etc/profile.d/oracle-xe.sh
. /etc/profile


echo "`date` - Iniciando o Oracle XE"

impdp () {
    DUMP_FILE=$(basename "$1")
    DUMP_NAME=${DUMP_FILE%.dmp} 
    cat > /tmp/impdp.sql << EOL
-- Impdp User
CREATE USER IMPDP IDENTIFIED BY IMPDP;
ALTER USER IMPDP ACCOUNT UNLOCK;
GRANT dba TO IMPDP WITH ADMIN OPTION;
-- New Scheme User
create or replace directory IMPDP as '/docker-entrypoint-initdb.d/';
create tablespace $DUMP_NAME datafile '/u01/app/oracle/oradata/$DUMP_NAME.dbf' size 1000M autoextend on next 100M maxsize unlimited;
create user $DUMP_NAME identified by $DUMP_NAME default tablespace $DUMP_NAME;
alter user $DUMP_NAME quota unlimited on $DUMP_NAME;
alter user $DUMP_NAME default role all;
grant connect, resource to $DUMP_NAME;
exit;
EOL

    su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/sqlplus -S / as sysdba @/tmp/impdp.sql"
    su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/impdp IMPDP/IMPDP directory=IMPDP dumpfile=$DUMP_FILE $IMPDP_OPTIONS nologfile=y"
    #Disable IMPDP user
    echo -e 'ALTER USER IMPDP ACCOUNT LOCK;\nexit;' | su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/sqlplus -S / as sysdba"
}


create_soma_schema () { 
    echo "`date` - Criando o usuário SOMA e o seu Tablespace. Usaremo a SOMA_PASSWD = $SOMA_PASSWD "
    
    ls -lat /database-data

    cat > /tmp/soma-schema.sql << EOL
-- Listando Usuário começando com S
select * from all_users where USERNAME like 'S%';
-- 
-- concedendo privilégios globais 
grant all on SYS.DBMS_CRYPTO to public; 
grant all on SYS.UTL_TCP to public; 

-- criando TableSpace para o SOMA
CREATE TABLESPACE TS_SOMA 
  LOGGING 
  DATAFILE '/database-data/soma.dbf' 
  SIZE 1000M 
  REUSE 
  AUTOEXTEND ON
  NEXT 100M 
  MAXSIZE 10000M 
  EXTENT MANAGEMENT LOCAL
; 

-- criando o usuario 
CREATE USER soma 
  identified by $SOMA_PASSWD 
  default tablespace TS_SOMA 
  temporary tablespace TEMP 
  quota unlimited on TS_SOMA 
; 

GRANT connect, create session, resource, dba TO SOMA WITH ADMIN OPTION;

-- tabela env_state para guardar o estado do ambiente de persistência

CREATE TABLE soma.env_state
(
  id          INT not null,
  state       INT not null,
  description VARCHAR2(80),
  date_added  TIMESTAMP
);
ALTER TABLE soma.env_state ADD (
  CONSTRAINT env_state_pk PRIMARY KEY (id));  
CREATE SEQUENCE soma.env_state_seq START WITH 1;
CREATE OR REPLACE TRIGGER soma.env_state_before_insert 
BEFORE INSERT ON env_state 
FOR EACH ROW
BEGIN
  SELECT soma.env_state_seq.NEXTVAL
  INTO   :new.id
  FROM   dual;
END;
/

INSERT INTO soma.env_state(id, state, description, date_added)
  VALUES(soma.env_state_seq.NEXTVAL, 1, 'tablespace ts_soma was created', sysdate);
commit;

INSERT INTO soma.env_state(id, state, description, date_added)
  VALUES(soma.env_state_seq.NEXTVAL, 2, 'soma user was created', sysdate);
commit;

select trim(max(state)) as current_env_state from soma.env_state;

exit;
EOL

    su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/sqlplus -S / as sysdba @/tmp/soma-schema.sql"
    echo -e 'select * from all_users;' | su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/sqlplus -S / as sysdba"
}

impFile() {
    echo "found file $1"
    case "$1" in
        *.sh)     echo "[IMPORT] $0: running $1"; . "$1" ;;
        *.sql)    echo "[IMPORT] $0: running $1"; echo "exit" | su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/sqlplus -S / as sysdba @$1"; echo ;;
        *.dmp)    echo "[IMPORT] $0: running $1"; impdp $1 ;;
        *)        echo "[IMPORT] $0: ignoring $1" ;;
    esac
}

case "$1" in
    '')
        #Check for mounted database files
        if [ "$(ls -A /u01/app/oracle/oradata 2> /dev/null)" ]; then
            echo "found files in /u01/app/oracle/oradata Using them instead of initial database"
            echo "XE:$ORACLE_HOME:N" >> /etc/oratab
            chown oracle:dba /etc/oratab
            chown 664 /etc/oratab
            printf "ORACLE_DBENABLED=false\nLISTENER_PORT=1521\nHTTP_PORT=8080\nCONFIGURE_RUN=true\n" > /etc/default/oracle-xe
            rm -rf /u01/app/oracle-product/11.2.0/xe/dbs
            ln -s /u01/app/oracle/dbs /u01/app/oracle-product/11.2.0/xe/dbs
        else
            echo "Database not initialized. Initializing database."

            if [ -z "$CHARACTER_SET" ]; then
                export CHARACTER_SET="AL32UTF8"
            fi

            printf "Setting up:\nprocesses=$processes\nsessions=$sessions\ntransactions=$transactions\n"
            echo "If you want to use different parameters set processes, sessions, transactions env variables and consider this formula:"
            printf "processes=x\nsessions=x*1.1+5\ntransactions=sessions*1.1\n"

            mv /u01/app/oracle-product/11.2.0/xe/dbs /u01/app/oracle/dbs
            ln -s /u01/app/oracle/dbs /u01/app/oracle-product/11.2.0/xe/dbs

            #Setting up processes, sessions, transactions.
            sed -i -E "s/processes=[^)]+/processes=$processes/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/init.ora
            sed -i -E "s/processes=[^)]+/processes=$processes/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/initXETemp.ora
            
            sed -i -E "s/sessions=[^)]+/sessions=$sessions/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/init.ora
            sed -i -E "s/sessions=[^)]+/sessions=$sessions/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/initXETemp.ora

            sed -i -E "s/transactions=[^)]+/transactions=$transactions/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/init.ora
            sed -i -E "s/transactions=[^)]+/transactions=$transactions/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/initXETemp.ora

            printf 8080\\n1521\\n${DEFAULT_SYS_PASS}\\n${DEFAULT_SYS_PASS}\\ny\\n | /etc/init.d/oracle-xe configure
            echo "Setting sys/system passwords"
            echo  alter user sys identified by \"$DEFAULT_SYS_PASS\"\; | su oracle -s /bin/bash -c "$ORACLE_HOME/bin/sqlplus -s / as sysdba" > /dev/null 2>&1
            echo  alter user system identified by \"$DEFAULT_SYS_PASS\"\; | su oracle -s /bin/bash -c "$ORACLE_HOME/bin/sqlplus -s / as sysdba" > /dev/null 2>&1

            echo "Database initialized. Please visit http://#containeer:8080/apex to proceed with configuration"
        fi

        /etc/init.d/oracle-xe start
        
        # TODO: testar também se tamanho é maior que zero (opção -s)
        if [ -f /database-data/soma.dbf ]; then
            echo "`date` - Arquivo /database-data/soma.dbf já existe. Assumindo que o usuário SOMA e o seu Tablespace já foram criados."
        else
            echo "Starting SOMA schema creation process"
            create_soma_schema $SOMA_PASSWD 
                    
            echo "Starting import scripts from '/docker-entrypoint-initdb.d':"

            for fn in $(ls -1 /docker-entrypoint-initdb.d/* 2> /dev/null)
            do
                # execute script if it didn't execute yet or if it was changed
                cat /docker-entrypoint-initdb.d/.cache 2> /dev/null | grep "$(md5sum $fn)" || impFile $fn
            done

            # clear cache
            if [ -e /docker-entrypoint-initdb.d/.cache ]; then
                rm /docker-entrypoint-initdb.d/.cache
            fi

            # regenerate cache
            ls -1 /docker-entrypoint-initdb.d/*.sh 2> /dev/null | xargs md5sum >> /docker-entrypoint-initdb.d/.cache
            ls -1 /docker-entrypoint-initdb.d/*.sql 2> /dev/null | xargs md5sum >> /docker-entrypoint-initdb.d/.cache
            ls -1 /docker-entrypoint-initdb.d/*.dmp 2> /dev/null | xargs md5sum >> /docker-entrypoint-initdb.d/.cache

            echo "Import finished"
            echo
        fi

        echo "Database ready to use. Enjoy! ;)"

        ##
        ## Workaround for graceful shutdown. ....ing oracle... ‿( ́ ̵ _-`)‿
        ##
        while [ "$END" == '' ]; do
            sleep 1
            trap "/etc/init.d/oracle-xe stop && END=1" INT TERM
        done
        ;;

    *)
        echo "Database is not configured. Please run /etc/init.d/oracle-xe configure if needed."
        exec "$@"
        ;;
esac
