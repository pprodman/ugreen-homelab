FROM python:3.13-slim

WORKDIR /dbt

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

WORKDIR /workspace

ENTRYPOINT ["dbt"]