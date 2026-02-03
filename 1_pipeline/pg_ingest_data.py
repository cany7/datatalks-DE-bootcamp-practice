#!/usr/bin/env python
# coding: utf-8

#Using argparse to avoid Hardcode for the parameters
import argparse
import pandas as pd
from sqlalchemy import create_engine
from tqdm.auto import tqdm

def run(args):
    #Read a sample of the data
    #Create the engine, using sqlalchemy to connect to postgres db
    engine = create_engine(f'postgresql://{args.user}:{args.password}@{args.host}:{args.port}/{args.database}')

    # Specify dtypes explicitly to avoid pandas chunk-based inference causing mixed-type warnings and unstable schemas
    dtype = {
        "VendorID": "Int64",
        "passenger_count": "Int64",
        "trip_distance": "float64",
        "RatecodeID": "Int64",
        "store_and_fwd_flag": "string",
        "PULocationID": "Int64",
        "DOLocationID": "Int64",
        "payment_type": "Int64",
        "fare_amount": "float64",
        "extra": "float64",
        "mta_tax": "float64",
        "tip_amount": "float64",
        "tolls_amount": "float64",
        "improvement_surcharge": "float64",
        "total_amount": "float64",
        "congestion_surcharge": "float64"
    }

    parse_dates = [
        "tpep_pickup_datetime",
        "tpep_dropoff_datetime"
    ]

    df_iter = pd.read_csv(
        args.url,
        dtype=dtype,
        parse_dates=parse_dates,
        iterator=True,
        #Not a regular dataframe here, a TextFileReader iterator gets 100,000 rows at a time
        chunksize= args.chunksize
    )

    target_table = 'yellow_taxi_data'

    # The integrated version, with using tqdm to show the progress bar; Create table first if not exists
    first = True

    for df_chunk in tqdm(df_iter):
        if first:
            # Create an empty table with schema
            df_chunk.head(0).to_sql(
                name=target_table,
                con=engine,
                if_exists="replace",
                index=False
            )
            first = False
            print("Table created")

        # Insert chunk
        df_chunk.to_sql(
            name=target_table,
            con=engine,
            if_exists="append",
            index=False
        )

        print("Inserted:", len(df_chunk))


if __name__ == '__main__':
    # Parse the arguments (url & postgres settings)
    parser = argparse.ArgumentParser(description='Ingest CSV data to Postgres')
    parser.add_argument('--year', type=int, help='year of the data', default=2021)
    parser.add_argument('--month', type=int, help='month of the data', default=1)

    parser.add_argument('--user', type=str, help='postgres user', default='root')
    parser.add_argument('--password', type=str, help='postgres password', default='root')
    parser.add_argument('--host', type=str, help='postgres host', default='localhost')
    parser.add_argument('--port', type=int, help='postgres port', default=5432)
    parser.add_argument('--database', type=str, help='postgres db', default='ny_taxi')
    parser.add_argument('--chunksize', type=int, help='chunksize', default=100000)
    pg_args = parser.parse_args()

    # Parameterized the url; month:02d means format the value as a decimal integer (d) with a minimum width of 2, padding with leading zeros (0) if needed
    # Add url as an attribute to the pg_args object
    prefix = 'https://github.com/DataTalksClub/nyc-tlc-data/releases/download/yellow/yellow_tripdata_'
    pg_args.url = f'{prefix}{pg_args.year}-{pg_args.month:02d}.csv.gz'

    run(pg_args)