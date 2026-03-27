from http.server import HTTPServer, BaseHTTPRequestHandler
import json, os

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({
            "message": "Hello depuis ECS Fargate !",
            "version": os.environ.get("APP_VERSION", "v1"),
            "host":    os.environ.get("HOSTNAME", "unknown")
        })
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, format, *args):
        print(f"[REQUEST] {self.address_string()} - {format % args}", flush=True)

if __name__ == "__main__":
    print("Serveur demarre sur port 80")
    HTTPServer(("", 80), Handler).serve_forever()
