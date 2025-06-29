FROM public.ecr.aws/lambda/python:3.11

# Aquí debemos usar requirements.txt para instalar las dependencias
RUN pip install psycopg2-binary

COPY handler.py .

CMD ["handler.handler"]
