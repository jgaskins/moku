FROM crystallang/crystal:0.31.1

RUN mkdir -p /moku
COPY . /moku
ADD /moku
WORKDIR /moku

RUN shards build --release

CMD ["build/moku"]
