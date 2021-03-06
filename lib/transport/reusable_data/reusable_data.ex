defmodule Transport.ReusableData do
  @moduledoc """
  The ReusableData bounded context.
  """

  alias Transport.ReusableData.{Dataset, Licence}
  alias Transport.Datagouvfr.Client.Datasets

  @pool DBConnection.Poolboy

  @doc """
  Returns the list of reusable datasets containing no validation errors.

  ## Examples

      iex> ReusableData.list_datasets
      ...> |> List.first
      ...> |> Map.get(:title)
      "Leningrad metro dataset"

  """
  @spec list_datasets :: [%Dataset{}]
  def list_datasets do
    query = %{
      anomalies: [],
      coordinates: %{"$ne" => nil},
      download_uri: %{"$ne" => nil},
    }

    :mongo
    |> Mongo.find("datasets", query, pool: @pool)
    |> Enum.to_list()
    |> Enum.map(&Dataset.new(&1))
    |> Enum.reduce([], fn(dataset, acc) ->
      dataset =
        dataset
        |> Dataset.assign(:error_count)
        |> Dataset.assign(:notice_count)
        |> Dataset.assign(:warning_count)
        |> Dataset.assign(:valid?)

      [dataset | acc]
    end)
    |> Enum.filter(&(&1.valid?))
  end

  @doc """
  Return one dataset by slug

  ## Examples

      iex> "leningrad-metro-dataset"
      ...> |> ReusableData.get_dataset
      ...> |> Map.get(:title)
      "Leningrad metro dataset"

      iex> ReusableData.get_dataset("")
      nil

      iex> "leningrad-metro-dataset"
      ...> |> ReusableData.get_dataset
      ...> |> Map.get(:valid?)
      true

  """
  @spec get_dataset(String.t) :: %Dataset{}
  def get_dataset(slug) do
    query = %{slug: slug}

    :mongo
    |> Mongo.find_one("datasets", query, pool: @pool)
    |> case do
      nil ->
        nil

      dataset ->
        dataset
        |> Dataset.new
        |> Dataset.assign(:error_count)
        |> Dataset.assign(:notice_count)
        |> Dataset.assign(:warning_count)
        |> Dataset.assign(:valid?)
    end
  end

  @doc """
  Creates a dataset.

  ## Examples

      iex> %{title: "Saintes"}
      ...> |> ReusableData.create_dataset
      ...> |> Map.get(:title)
      "Saintes"

      iex> %{"title" => "Rochefort"}
      ...> |> ReusableData.create_dataset
      ...> |> Map.get(:title)
      "Rochefort"

  """
  @spec create_dataset(map()) :: %Dataset{}
  def create_dataset(%{} = attrs) do
    {:ok, result} = Mongo.insert_one(:mongo, "datasets", attrs, pool: @pool)
    query         = %{"_id"  => result.inserted_id}

    :mongo
    |> Mongo.find_one("datasets", query, pool: @pool)
    |> Dataset.new
  end

  @doc """
  Updates a dataset.

  ## Examples

      iex> %{title: "Creative title"}
      ...> |> ReusableData.create_dataset
      ...> |> ReusableData.update_dataset(%{title: "Lame title"})
      :ok

      iex> ReusableData.update_dataset(%Dataset{}, %{title: "Alphaville"})
      {:error, :enodoc}

  """
  @spec update_dataset(%Dataset{}, map()) :: :ok | {:error, :enodoc}
  def update_dataset(%Dataset{} = dataset, %{} = attrs) do
    query     = %{"_id"  => dataset._id}
    changeset = %{"$set" => attrs}

    :mongo
    |> Mongo.find_one_and_update("datasets", query, changeset, pool: @pool)
    |> case do
      {:ok, nil} -> {:error, :enodoc}
      {:ok, _}   -> :ok
    end
  end

  @doc """
  Builds a licence.

  ## Examples

      iex> %{name: "fr-lo"}
      ...> |> ReusableData.build_licence
      ...> |> Map.get(:name)
      "Open Licence"

      iex> %{name: "Libertarian"}
      ...> |> ReusableData.build_licence
      ...> |> Map.get(:name)
      nil

      iex> %{}
      ...> |> ReusableData.build_licence
      ...> |> Map.get(:alias)
      nil

  """
  @spec build_licence(map()) :: %Licence{}
  def build_licence(%{} = attrs) do
    Licence.new(attrs)
  end

  def get_dataset_id(conn, dataset) do
    conn
    |> Datasets.get(dataset.slug)
    |> case do
      {:ok, %{"id" => id}} -> id
      {:ok, _}            -> nil
      {:error, _}          -> nil
    end
  end
end
