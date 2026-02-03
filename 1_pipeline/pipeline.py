# Simulates a parameterized ETL step: read data into a DataFrame, process it, and write it to a Parquet file named by the input argument for downstream pipeline use.
import sys
import pandas as pd

print('args', sys.argv)
month = int(sys.argv[1])

df = pd.DataFrame({"A": [1, 2], "B": [3, 4]})
print(df.head())

df.to_parquet(f"output_{sys.argv[1]}.parquet")

print(f'month={month}')