defmodule NotificationSystem.Encryption do
  @moduledoc """
  Enkripcija i dekripcija poruka za sigurnu komunikaciju.

  Funkcionalnosti:
  - AES-256-GCM enkripcija
  - Automatsko upravljanje kljucevima
  - Verifikacija integriteta poruka
  - Podrska za end-to-end enkripciju
  """
  require Logger

  @algorithm :aes_256_gcm
  @key_size 32  # 256 bits
  @iv_size 16   # 128 bits
  @tag_size 16  # 128 bits

  @doc """
  Generisanje novog encryption kljuca
  """
  def generate_key do
    :crypto.strong_rand_bytes(@key_size)
  end

  @doc """
  Encrypts poruku sa datim klucem

  Returns {:ok, {ciphertext, tag, iv}} or {:error, reason}
  """
  def encrypt(message, key) when byte_size(key) == @key_size do
    try do
      # Serijalizuj poruku u binarni format
      payload = :erlang.term_to_binary(message)

      # Generisanje slucajnog broja
      iv = :crypto.strong_rand_bytes(@iv_size)

      # Encrypt with AES-GCM
      {ciphertext, tag} = :crypto.crypto_one_time_aead(
        @algorithm,
        key,
        iv,
        payload,
        <<>>,  # AAD (dodatni authenticated podaci)
        @tag_size,
        true   # encrypt fleg
      )

      encrypted_data = %{
        ciphertext: Base.encode64(ciphertext),
        tag: Base.encode64(tag),
        iv: Base.encode64(iv),
        algorithm: @algorithm
      }

      {:ok, encrypted_data}
    rescue
      error ->
        Logger.error("Encryption failed: #{inspect(error)}")
        {:error, :encryption_failed}
    end
  end

  def encrypt(_message, _key) do
    {:error, :invalid_key_size}
  end

  @doc """
  Decrypts sifrovanu poruku pomocu datog kljuca

  Returns {:ok, message} or {:error, reason}
  """
  def decrypt(encrypted_data, key) when byte_size(key) == @key_size do
    try do
      ciphertext = Base.decode64!(encrypted_data.ciphertext)
      tag = Base.decode64!(encrypted_data.tag)
      iv = Base.decode64!(encrypted_data.iv)

      # Decrypt with AES-GCM
      payload = :crypto.crypto_one_time_aead(
        @algorithm,
        key,
        iv,
        ciphertext,
        <<>>,  # AAD
        tag,
        false  # decrypt flag
      )

      # Deserijalizuj poruku
      message = :erlang.binary_to_term(payload)

      {:ok, message}
    rescue
      error ->
        Logger.error("Decryption failed: #{inspect(error)}")
        {:error, :decryption_failed}
    end
  end

  def decrypt(_encrypted_data, _key) do
    {:error, :invalid_key_size}
  end

  @doc """
  Kreiranje hes poruke radi provere integrity verifikacije
  """
  def hash(message) do
    :crypto.hash(:sha256, :erlang.term_to_binary(message))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Provera integriteta poruka koriscenjem hesa
  """
  def verify_hash(message, expected_hash) do
    actual_hash = hash(message)
    actual_hash == expected_hash
  end

  @doc """
  Sifruje poruku i ukljucuje proveru integriteta
  """
  def secure_encrypt(message, key) do
    message_hash = hash(message)

    payload = %{
      message: message,
      hash: message_hash,
      timestamp: DateTime.utc_now()
    }

    encrypt(payload, key)
  end

  @doc """
  Desifruje poruku i proverava integritet poruke
  """
  def secure_decrypt(encrypted_data, key) do
    case decrypt(encrypted_data, key) do
      {:ok, payload} ->
        if verify_hash(payload.message, payload.hash) do
          {:ok, payload.message}
        else
          {:error, :integrity_check_failed}
        end

      error ->
        error
    end
  end

  @doc """
  Generisanje par kljuceva za asimetricno sifrovanje
  """
  def generate_keypair do
    # Koristeci Ed25519 za digitalne potpise
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    %{
      public_key: Base.encode64(public_key),
      private_key: Base.encode64(private_key),
      algorithm: :ed25519
    }
  end

  @doc """
  Potpisuje poruku sa privatnim kljucem
  """
  def sign_message(message, private_key_b64) do
    try do
      private_key = Base.decode64!(private_key_b64)
      payload = :erlang.term_to_binary(message)

      signature = :crypto.sign(:eddsa, :sha512, payload, [private_key, :ed25519])

      %{
        message: message,
        signature: Base.encode64(signature),
        timestamp: DateTime.utc_now()
      }
    rescue
      error ->
        Logger.error("Signing failed: #{inspect(error)}")
        {:error, :signing_failed}
    end
  end

  @doc """
  Proverava potpisanu poruku javnim kljucem
  """
  def verify_signature(signed_data, public_key_b64) do
    try do
      public_key = Base.decode64!(public_key_b64)
      signature = Base.decode64!(signed_data.signature)
      payload = :erlang.term_to_binary(signed_data.message)

      valid = :crypto.verify(:eddsa, :sha512, payload, signature, [public_key, :ed25519])

      if valid do
        {:ok, signed_data.message}
      else
        {:error, :invalid_signature}
      end
    rescue
      error ->
        Logger.error("Signature verification failed: #{inspect(error)}")
        {:error, :verification_failed}
    end
  end

  @doc """
  Funkcija za generisanje slucajnog tokena
  """
  def generate_token(length \\ 32) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> binary_part(0, length)
  end
end
