create database rainloopdb;

create user 'rainloopuser'
  identified by 'rainlooppassword'; --choose a sensible password here if you want to change it

grant all privileges
  on rainloopdb.*
  to rainloopuser;

flush privileges;
