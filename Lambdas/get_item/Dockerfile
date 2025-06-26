FROM public.ecr.aws/lambda/python:3.11

RUN pip install psycopg2-binary

COPY handler.py .

CMD ["handler.handler"]