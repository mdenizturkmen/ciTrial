FROM alpine:3.14

WORKDIR catkin_ws

RUN echo "hello world" > readme

COPY myfolder ./myfolder

CMD echo "hey, ho, ho"
