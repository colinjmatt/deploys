create database rainloopdb;

create user 'rainloopuser'
  identified by '$rainlooppassword';

grant all privileges
  on rainloopdb.*
  to rainloopuser;

flush privileges;
