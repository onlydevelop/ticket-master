FROM golang:1.23-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /event-service .

FROM gcr.io/distroless/static-debian12
COPY --from=build /event-service /event-service
ENTRYPOINT ["/event-service"]
