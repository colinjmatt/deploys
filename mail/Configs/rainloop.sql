create database rainloopdb;
grant all privileges    on rainloopdb.*
                        to 'rainloopuser'@'localhost'
                        identified by 'rainlooppassword'; --choose a sensible password here if you want to change it
flush privileges;
