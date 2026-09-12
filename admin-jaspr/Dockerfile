FROM dart:stable AS build

WORKDIR /app

RUN dart install jaspr_cli

COPY pubspec.yaml analysis_options.yaml ./
RUN dart pub get

COPY lib ./lib
COPY web ./web

RUN /root/.pub-cache/bin/jaspr build

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/jaspr/ /usr/share/nginx/html/

EXPOSE 8080
