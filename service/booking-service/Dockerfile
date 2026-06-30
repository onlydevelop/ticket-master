FROM golang:1.23-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o /booking-service .

FROM gcr.io/distroless/static-debian12
COPY --from=build /booking-service /booking-service
ENTRYPOINT ["/booking-service"]
