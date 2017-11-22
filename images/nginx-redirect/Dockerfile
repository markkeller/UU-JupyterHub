FROM nginx:alpine
MAINTAINER markkeller <mjkeller@gmail.com> 

COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./ssl.conf /etc/nginx/ssl.conf

RUN mkdir /etc/nginx/ssl
COPY ./ssl/* /etc/nginx/ssl/

RUN chmod 700 /etc/nginx/ssl && \
    chmod 600 /etc/nginx/ssl/*

