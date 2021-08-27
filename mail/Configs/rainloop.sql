create database rainloop;

create user 'rainloopuser'@'localhost'
  identified by '$rainlooppassword';

grant all privileges
  on rainloopdb.*
  to 'rainloopuser'@'localhost';

flush privileges;
