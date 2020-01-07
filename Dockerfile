FROM crystallang/crystal:0.32.1

ADD . /moku
WORKDIR /moku

RUN shards build --release

EXPOSE 8080/tcp

CMD ["bin/moku"]
