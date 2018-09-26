FROM elixir:1.7.3
VOLUME /Users/kiro/test:/data
RUN echo "hello-world!!!!" > /data/myfile.txt

CMD ["cat", "/data/myfile.txt"]
