import { Table, TableRow, TableHeader } from '@/components/Common/Table';
import { Driver, setDriver } from '@/dataSources';
import { QualifiedTable } from '@/metadata/types';

import { useAppDispatch } from '@/store';
import React from 'react';
import { useTablePrimaryKey } from '..';

export const PrimaryKeys = ({
  driver,
  currentDatasource,
  table,
}: {
  driver: Driver;
  currentDatasource: string;
  table: QualifiedTable;
}) => {
  const dispatch = useAppDispatch();
  React.useEffect(() => {
    if (currentDatasource) {
      dispatch({
        type: 'Data/UPDATE_CURRENT_DATA_SOURCE',
        source: currentDatasource,
      });
    }
    if (driver) {
      setDriver(driver);
    }
  }, [currentDatasource, dispatch, driver]);

  const {
    data: primaryKey,
    isLoading,
    isSuccess,
    isError,
    isIdle,
    error,
  } = useTablePrimaryKey(table, { retry: 0 });
  const keys = React.useMemo(() => Object.keys(primaryKey ?? {}), [primaryKey]);
  const entries = React.useMemo(() => Object.values(primaryKey ?? {}), [
    primaryKey,
  ]);

  if (isError) {
    return <p className="text-red-500">Error: {error?.message}</p>;
  }

  if (isLoading || isIdle) {
    return <p>Loading...</p>;
  }

  return (
    <div>
      <h1 className="prose-xl">useTablePrimaryKeys</h1>
      <p className="prose-lg mb-8">
        Primary Key on{' '}
        <b>
          {table.schema}.{table.name}
        </b>{' '}
        table
      </p>
      {isSuccess && (
        <Table rowCount={1} columnCount={keys?.length ?? 0}>
          <TableHeader headers={keys.length ? keys : ['EmptyValue']} />
          <TableRow
            entries={entries.length ? entries : ['null']}
            index=""
            readonly
            renderCol={({ data }) =>
              typeof data === 'string' ? data : JSON.stringify(data)
            }
          />
        </Table>
      )}
    </div>
  );
};
