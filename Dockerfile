FROM ubuntu:24.04 AS build
ARG FLUTTER_VERSION=3.47.5
ENV FLUTTER_ROOT=/opt/flutter
ENV PATH="${FLUTTER_ROOT}/bin:${PATH}"
ENV CI=true FLUTTER_SUPPRESS_ANALYTICS=true
RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates curl git unzip xz-utils zip libglu1-mesa libstdc++6 \
	&& rm -rf /var/lib/apt/lists/*
# Use the official SDK tag, not a third-party image that may lack this version.
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
	https://github.com/flutter/flutter.git "${FLUTTER_ROOT}" \
	&& flutter config --no-analytics \
	&& flutter precache --web \
	&& flutter --version
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN dart run tool/bundle_web_client.dart
RUN cd server && dart pub get && dart compile exe bin/server.dart -o /app/quizmo-server

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libstdc++6 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/quizmo-server ./quizmo-server
COPY --from=build /app/build/web ./web
USER 10001:10001
ENV WEB_ROOT=/app/web BIND_ADDRESS=0.0.0.0 PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/quizmo-server"]
