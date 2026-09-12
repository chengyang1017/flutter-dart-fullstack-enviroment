FROM dart:stable AS build

WORKDIR /app

RUN dart pub global activate jaspr_cli
ENV PATH="${PATH}:/root/.pub-cache/bin"

COPY pubspec.yaml analysis_options.yaml ./
RUN dart pub get

COPY lib ./lib
COPY web ./web

RUN jaspr build --no-ssr

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/ /usr/share/nginx/html/

EXPOSE 8080
