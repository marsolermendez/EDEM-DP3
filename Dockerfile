FROM python:3.11-slim

WORKDIR /app

COPY app/ .

RUN pip install --no-cache-dir flask requests psycopg2-binary

ENV PORT=8080
EXPOSE 8080

RUN cat app.py 

CMD ["python", "app.py"]

