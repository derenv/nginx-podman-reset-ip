#!/usr/bin/env python3

##
# Name:
# set_ip.py
#
# Description:
# Python script for updating an nginx reverse proxy manager sqlite database
# Updates proxy address for specific domain to the passed ip address
# Does a validation query to check result!
#
# Authors:
# Deren Vural (@derenv)
# Oscar Mccabe (@oscarmccabe1998)
#
# Notes:
# https://stackoverflow.com/questions/22488763/sqlite-insert-query-not-working-with-python
# https://stackoverflow.com/questions/25371636/how-to-get-sqlite-result-error-codes-in-python
# https://www.digitalocean.com/community/tutorials/how-to-use-the-sqlite3-module-in-python-3
##


# Imports
import sqlite3
import traceback
import sys
from contextlib import closing

# Functions
def update(db_path, data):
    # Create prepared statement
    query = "UPDATE proxy_host SET forward_host = ? WHERE domain_names = ?"

    # Open database connection
    with closing(sqlite3.connect(db_path)) as conn:
        # Check database connection
        if conn.total_changes == 0:
            # Open cursor
            with closing(conn.cursor()) as cursor:
                try:
                    # Execute & Commit Query
                    cursor.execute(
                        query,
                        data
                    )
                    conn.commit()

                    # Return exit code
                    return 0
                except sqlite3.Error as er:
                    # Print error message
                    print('SQLite error: %s' % (' '.join(er.args)))
                    print("Exception class is: ", er.__class__)
                    print('SQLite traceback: ')
                    exc_type, exc_value, exc_tb = sys.exc_info()
                    print(traceback.format_exception(exc_type, exc_value, exc_tb))

                    # Return exit code
                    return 2
        else:
            # Print error message
            print("Database connection failed..")

            # Return exit code
            return 2


def select(db_path, data, check_value):
    # Create prepared statement
    query = "SELECT * FROM proxy_host WHERE domain_names = ?"

    # Open database connection
    with closing(sqlite3.connect(db_path)) as conn:
        # Check database connection
        if conn.total_changes == 0:
            # Open cursor
            with closing(conn.cursor()) as cursor:
                try:
                    # Execute & Commit Query
                    result = cursor.execute(
                        query,
                        data
                    ).fetchall()
                    conn.commit()

                    # Check output against check value
                    if result[0][6] == check_value:
                        # Return exit code
                        return 0
                    else:
                        # Return exit code
                        return 1
                except sqlite3.Error as er:
                    # Print error message
                    print('SQLite error: %s' % (' '.join(er.args)))
                    print("Exception class is: ", er.__class__)
                    print('SQLite traceback: ')
                    exc_type, exc_value, exc_tb = sys.exc_info()
                    print(traceback.format_exception(exc_type, exc_value, exc_tb))

                    # Return exit code
                    return 2
        else:
            # Print error message
            print("Database connection failed..")

            # Return exit code
            return 2


def main():
    # Arguments
    db_path = sys.argv[1]
    new_ip = sys.argv[2]
    domain_name = sys.argv[3]

    # Make changes with update query
    result = update(db_path, (new_ip, domain_name))

    # Abort check if already failed
    if result == 0:
        # Check success with select query
        result = select(db_path, (domain_name,), new_ip)

    # Return exit code
    sys.exit(result)

if __name__ == "__main__":
    main()
