docker-oracle-xe-11g
============================
[![](https://images.microbadger.com/badges/image/sath89/oracle-xe-11g.svg)](https://microbadger.com/images/sath89/oracle-xe-11g "Get your own image badge on microbadger.com")

[![](https://images.microbadger.com/badges/version/sath89/oracle-xe-11g.svg)](https://microbadger.com/images/sath89/oracle-xe-11g "Get your own version badge on microbadger.com")

Oracle Express Edition 11g Release 2 on Ubuntu 14.04.1 LTS

**TODO: corrigir isso**
This **Dockerfile** is a [trusted build](https://registry.hub.docker.com/u/sath89/oracle-xe-11g/) of [Docker Registry](https://registry.hub.docker.com/).


## Pendências

* Em entrepoint.sh usar `node checkState.js` para obter o Estado atual da Persitência

```javascript
/*
  * NAME
  *   checkState.js
  *
  * DESCRIPTION
  *   
  */

var oracledb = require('oracledb');
var dbConfig = require('./dbconfig.js');

oracledb.getConnection(
  {
    user          : dbConfig.user,
    password      : dbConfig.password,
    connectString : dbConfig.connectString
  },
  function(err, connection) {
    if (err) {
      console.error(err.message);
      return;
    }
    // console.log('Connection was successful!');

    connection.execute(
      `SELECT trim(max(state)) as current_env_state
       FROM soma.env_state
       WHERE 1 = :value`,
      [1],  // bind value for :value
      function(err, result) {
        // console.log('Executing SQL command !');
        if (err) {
          console.error(err.message);
          doRelease(connection);
          return;
        }
        // console.log("result.rows is :");
        console.log(result.rows[0][0]);
        doRelease(connection);
      }
    );
  },
);

function doRelease(connection) {
  connection.close(
    function(err) {
      if (err)
        console.error(err.message);
    });
}
```


```javascript
 /*
 * NAME
 *   dbconfig.js
 *
 * DESCRIPTION
 *   Holds the credentials used by node-oracledb examples to connect
 *   to the database.  Production applications should consider using
 *   External Authentication to avoid hard coded credentials.
 *
 *   To create a database user see https://www.youtube.com/watch?v=WDJacg0NuLo
 *
 *   Applications can set the connectString value to an Easy Connect
 *   string, or a Net Service Name from a tnsnames.ora file or
 *   external naming service, or it can be the name of a local Oracle
 *   database instance.
 *
 *   If node-oracledb is linked with Instant Client, then an Easy
 *   Connect string is generally appropriate.  The syntax is:
 *
 *     [//]host_name[:port][/service_name][:server_type][/instance_name]
 *
 *   Commonly just the host_name and service_name are needed
 *   e.g. "localhost/orclpdb" or "localhost/XE"
 *
 *   If using a tnsnames.ora file, the file can be in a default
 *   location such as $ORACLE_HOME/network/admin/tnsnames.ora or
 *   /etc/tnsnames.ora.  Alternatively set the TNS_ADMIN environment
 *   variable and put the file in $TNS_ADMIN/tnsnames.ora.
 *
 *   If connectString is not specified, the empty string "" is used
 *   which indicates to connect to the local, default database.
 *
 *   External Authentication can be used by setting the optional
 *   property externalAuth to true.  External Authentication allows
 *   applications to use an external password store such as Oracle
 *   Wallet so passwords do not need to be hard coded into the
 *   application.  The user and password properties for connecting or
 *   creating a pool should not be set when externalAuth is true.
 *
 * TROUBLESHOOTING
 *   Errors like:
 *     ORA-12541: TNS:no listener
 *   or
 *     ORA-12154: TNS:could not resolve the connect identifier specified
 *   indicate connectString is invalid.
 *
 *   The error:
 *     ORA-12514: TNS:listener does not currently know of requested in connect descriptor
 *   indicates connectString is invalid.  You are reaching a computer
 *   with Oracle installed but the service name isn't known.
 *   Use 'lsnrctl services' on the database server to find available services
 */

module.exports = {
  user          : process.env.NODE_ORACLEDB_USER || "soma",

  // Instead of hard coding the password, consider prompting for it,
  // passing it in an environment variable via process.env, or using
  // External Authentication.
  password      : process.env.NODE_ORACLEDB_PASSWORD || "soma_secret",

  // For information on connection strings see:
  // https://oracle.github.io/node-oracledb/doc/api.html#connectionstrings
  connectString : process.env.NODE_ORACLEDB_CONNECTIONSTRING || "localhost/XE",

  // Setting externalAuth is optional.  It defaults to false.  See:
  // https://oracle.github.io/node-oracledb/doc/api.html#extauth
  externalAuth  : process.env.NODE_ORACLEDB_EXTERNALAUTH ? true : false
};
```

### Installation

    docker pull sath89/oracle-xe-11g

Run with 8080 and 1521 ports opened:

    docker run -d -p 8080:8080 -p 1521:1521 sath89/oracle-xe-11g

Run with data on host and reuse it:

    docker run -d -p 8080:8080 -p 1521:1521 -v /my/oracle/data:/u01/app/oracle sath89/oracle-xe-11g

Run with customization of processes, sessions, transactions
This customization is needed on the database initialization stage. If you are using mounted folder with DB files this is not used:

    ##Consider this formula before customizing:
    #processes=x
    #sessions=x*1.1+5
    #transactions=sessions*1.1
    docker run -d -p 8080:8080 -p 1521:1521 -v /my/oracle/data:/u01/app/oracle\
    -e processes=1000 \
    -e sessions=1105 \
    -e transactions=1215 \
    sath89/oracle-xe-11g

Run with custom sys password:

    docker run -d -p 8080:8080 -p 1521:1521 -e DEFAULT_SYS_PASS=sYs-p@ssw0rd sath89/oracle-xe-11g

Connect database with following setting:

    hostname: localhost
    port: 1521
    sid: xe
    username: system
    password: oracle

Password for SYS & SYSTEM:

    oracle

Connect to Oracle Application Express web management console with following settings:

    http://localhost:8080/apex
    workspace: INTERNAL
    user: ADMIN
    password: oracle

Apex upgrade up to v 5.*

    docker run -it --rm --volumes-from ${DB_CONTAINER_NAME} --link ${DB_CONTAINER_NAME}:oracle-database -e PASS=YourSYSPASS sath89/apex install
Details could be found here: https://github.com/MaksymBilenko/docker-oracle-apex

Auto import of sh sql and dmp files

    docker run -d -p 8080:8080 -p 1521:1521 -v /my/oracle/data:/u01/app/oracle -v /my/oracle/init/sh_sql_dmp_files:/docker-entrypoint-initdb.d sath89/oracle-xe-11g

**In case of using DMP imports dump file should be named like ${IMPORT_SCHEME_NAME}.dmp**
**User credentials for imports are  ${IMPORT_SCHEME_NAME}/${IMPORT_SCHEME_NAME}**

**In case of any issues please post it [here](https://github.com/MaksymBilenko/docker-oracle-xe-11g/issues).**


**CHANGELOG**
* Added auto-import using volume /docker-entrypoint-initdb.d for *.sh *.sql *.dmp
* Fixed issue with reusable mounted data
* Fixed issue with ownership of mounted data folders
* Fixed issue with Gracefull shutdown of service
* Reduse size of image from 3.8G to 825Mb
* Database initialization moved out of the image build phase. Now database initializes at the containeer startup with no database files mounted
* Added database media reuse support outside of container
* Added graceful shutdown on containeer stop
* Removed sshd

