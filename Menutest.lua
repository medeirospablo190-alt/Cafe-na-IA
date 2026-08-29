--==============================================================
-- UPLOAD CONFIG
--==============================================================

CONFIG.BaseURL =
	"https://SEU-SITE.onrender.com"

-- Se o seu Render tiver UPLOAD_TOKEN configurado,
-- coloque o MESMO token aqui.
-- Caso não tenha, deixe vazio.
CONFIG.UploadToken =
	""

-- Aproximadamente 1.5 MB por chunk.
-- Bem abaixo do limite de 6 MB do server.js.
CONFIG.UploadChunkTargetBytes =
	1.5 * 1024 * 1024

CONFIG.UploadRetries =
	3

CONFIG.UploadRetryDelay =
	1.25


--==============================================================
-- NORMALIZAR BASE URL
--==============================================================

local function normalizeBaseURL(url)

	url =
		tostring(url or "")

	url =
		url:gsub(
			"/+$",
			""
		)

	return url

end


--==============================================================
-- HTTP REQUEST DETECTOR
--==============================================================

local function getRequestFunction()

	if type(request) ==
		"function"
	then
		return request
	end


	if type(http_request) ==
		"function"
	then
		return http_request
	end


	if syn
		and
		type(syn.request) ==
			"function"
	then

		return syn.request
	end


	if http
		and
		type(http.request) ==
			"function"
	then

		return http.request
	end


	return nil

end


--==============================================================
-- RESPONSE HELPERS
--==============================================================

local function responseStatus(
	response
)

	if type(response) ~=
		"table"
	then

		return 0
	end


	return tonumber(
		response.StatusCode
		or
		response.Status
		or
		response.status
		or
		response.status_code
	) or 0

end


local function responseBody(
	response
)

	if type(response) ~=
		"table"
	then

		return ""
	end


	return tostring(
		response.Body
		or
		response.body
		or
		response.Response
		or
		response.response
		or
		""
	)

end


local function decodeJSON(
	text
)

	if type(text) ~=
		"string"
		or
		text == ""
	then

		return nil
	end


	local ok,
		result =
		pcall(function()

			return HttpService:
				JSONDecode(
					text
				)

		end)


	if ok
		and
		type(result) ==
			"table"
	then

		return result
	end


	return nil

end


--==============================================================
-- POST JSON
--==============================================================

local function postJSON(
	path,
	data,
	statusCallback
)

	local requestFunction =
		getRequestFunction()


	if not requestFunction then

		return false,
			nil,
			"HTTP request indisponível"

	end


	local baseURL =
		normalizeBaseURL(
			CONFIG.BaseURL
		)


	if baseURL == "" then

		return false,
			nil,
			"CONFIG.BaseURL não configurado"

	end


	----------------------------------------------------------
	-- TOKEN
	----------------------------------------------------------

	if CONFIG.UploadToken
		and
		CONFIG.UploadToken ~= ""
	then

		data.token =
			CONFIG.UploadToken

	end


	----------------------------------------------------------
	-- ENCODE
	----------------------------------------------------------

	local encodeOK,
		body =
		pcall(function()

			return HttpService:
				JSONEncode(
					data
				)

		end)


	if not encodeOK then

		return false,
			nil,
			"Falha ao gerar JSON: "
			..
			safeString(body)

	end


	local lastError =
		nil


	for attempt = 1,
		CONFIG.UploadRetries
	do

		if statusCallback then

			statusCallback(
				"Tentativa "
				..
				tostring(attempt)
				..
				"/"
				..
				tostring(
					CONFIG.UploadRetries
				)
			)

		end


		local ok,
			response =
			pcall(function()

				return requestFunction({

					Url =
						baseURL
						..
						path,

					Method =
						"POST",

					Headers = {

						["Content-Type"] =
							"application/json",

						["Accept"] =
							"application/json",
					},

					Body =
						body,
				})

			end)


		if ok then

			local status =
				responseStatus(
					response
				)


			local responseText =
				responseBody(
					response
				)


			local decoded =
				decodeJSON(
					responseText
				)


			if status >= 200
				and
				status < 300
			then

				return true,
					decoded,
					responseText

			end


			local message =
				decoded
				and
				(
					decoded.message
					or
					decoded.error
				)


			lastError =
				"HTTP "
				..
				tostring(status)
				..
				(
					message
					and
					(
						" • "
						..
						tostring(
							message
						)
					)
					or
					""
				)

		else

			lastError =
				safeString(
					response
				)

		end


		if attempt <
			CONFIG.UploadRetries
		then

			task.wait(
				CONFIG.UploadRetryDelay
				*
				attempt
			)

		end

	end


	return false,
		nil,
		lastError
		or
		"Falha HTTP"

end


--==============================================================
-- CALCULA TAMANHO JSON
--==============================================================

local function encodedSize(
	value
)

	local ok,
		encoded =
		pcall(function()

			return HttpService:
				JSONEncode(
					value
				)

		end)


	if not ok then

		return math.huge
	end


	return #encoded

end


--==============================================================
-- CRIA CHUNKS
--==============================================================

local function buildUploadChunks(
	records
)

	local chunks = {}

	local current = {}

	local currentBytes =
		2


	local limit =
		CONFIG.UploadChunkTargetBytes


	for index,
		record
		in ipairs(records)
	do

		local recordBytes =
			encodedSize(
				record
			)


		------------------------------------------------------
		-- Um registro sozinho não pode ultrapassar o limite
		------------------------------------------------------

		if recordBytes >= limit then

			if #current > 0 then

				chunks[
					#chunks + 1
				] = current


				current = {}

				currentBytes =
					2

			end


			chunks[
				#chunks + 1
			] = {
				record
			}


		else

			--------------------------------------------------
			-- +1 = vírgula aproximada do array JSON
			--------------------------------------------------

			if
				#current > 0

				and

				currentBytes
				+
				recordBytes
				+
				1
				>
				limit
			then

				chunks[
					#chunks + 1
				] = current


				current = {}

				currentBytes =
					2

			end


			current[
				#current + 1
			] = record


			currentBytes +=
				recordBytes
				+
				1

		end


		------------------------------------------------------
		-- Evita travar celular
		------------------------------------------------------

		if index % 150 ==
			0
		then

			task.wait()

		end

	end


	if #current > 0 then

		chunks[
			#chunks + 1
		] = current

	end


	----------------------------------------------------------
	-- /upload/finish exige pelo menos 1 chunk
	----------------------------------------------------------

	if #chunks == 0 then

		chunks[1] = {}

	end


	return chunks

end


--==============================================================
-- CANCELA UPLOAD SE DER ERRO
--==============================================================

local function cancelUpload(
	uploadId
)

	if not uploadId then
		return
	end


	pcall(function()

		postJSON(

			"/upload/cancel",

			{
				uploadId =
					uploadId
			}

		)

	end)

end


--==============================================================
-- UPLOAD REPORT
--
-- PROTOCOLO:
--
-- /upload/start
-- /upload/chunk
-- /upload/finish
--==============================================================

local function uploadReport()

	if State.Uploading then

		return false,
			"Upload já está em andamento"

	end


	if State.Running then

		return false,
			"Interrompa o scanner antes de enviar"

	end


	local baseURL =
		normalizeBaseURL(
			CONFIG.BaseURL
		)


	if baseURL == "" then

		return false,
			"Configure CONFIG.BaseURL"

	end


	State.Uploading =
		true


	local uploadId =
		nil


	local function finishWithError(
		message
	)

		if uploadId then

			cancelUpload(
				uploadId
			)

		end


		State.Uploading =
			false


		return false,
			message

	end


	--==========================================================
	-- NOME
	--==========================================================

	local filename =
		string.format(

			"Cafeina_WeaponBallistics_%d_%s.json",

			game.PlaceId,

			os.date(
				"%Y%m%d_%H%M%S"
			)

		)


	--==========================================================
	-- 1. START
	--==========================================================

	Status.Text =
		"Iniciando upload..."


	local startOK,
		startData,
		startRaw =
		postJSON(

			"/upload/start",

			{

				filename =
					filename,

				source =
					"cafeina-weapon-research-v2-continuous",

				metadata = {

					scanner =
						CONFIG.Scanner,

					version =
						CONFIG.Version,

					area =
						"WeaponBallistics",

					placeId =
						game.PlaceId,

					gameId =
						game.GameId,

					records =
						#State.Records,

					passes =
						State.Passes,

					approxBytes =
						State.ApproxBytes,

					shots =
						State.ShotCounter,

					effects =
						State.EffectCounter,

					signatures =
						State.SignatureCounter,
				},
			}

		)


	if not startOK then

		return finishWithError(

			"START: "
			..
			safeString(
				startRaw
			)

		)

	end


	uploadId =
		startData
		and
		startData.uploadId


	if not uploadId then

		return finishWithError(
			"Servidor não retornou uploadId"
		)

	end


	--==========================================================
	-- 2. BUILD CHUNKS
	--==========================================================

	Status.Text =
		"Preparando arquivos..."


	local chunks =
		buildUploadChunks(
			State.Records
		)


	local totalChunks =
		#chunks


	--==========================================================
	-- 3. SEND CHUNKS
	--==========================================================

	for index,
		objects
		in ipairs(chunks)
	do

		if State.Interrupted
			and
			State.Running
		then

			return finishWithError(
				"Upload interrompido"
			)

		end


		local percent =
			math.floor(
				(index - 1)
				/
				totalChunks
				*
				100
			)


		Status.Text =
			string.format(

				"Enviando %d/%d • %d%%",

				index,

				totalChunks,

				percent

			)


		local chunkOK,
			_chunkData,
			chunkError =
			postJSON(

				"/upload/chunk",

				{

					uploadId =
						uploadId,

					index =
						index,

					objects =
						objects,
				}

			)


		if not chunkOK then

			return finishWithError(

				"CHUNK "
				..
				tostring(index)
				..
				": "
				..
				safeString(
					chunkError
				)

			)

		end


		------------------------------------------------------
		-- Libera referência do chunk já enviado
		------------------------------------------------------

		chunks[index] =
			nil


		task.wait(
			0.03
		)

	end


	--==========================================================
	-- 4. FINISH
	--==========================================================

	Status.Text =
		"Finalizando upload..."


	local finishOK,
		finishData,
		finishError =
		postJSON(

			"/upload/finish",

			{

				uploadId =
					uploadId,

				totalChunks =
					totalChunks,
			}

		)


	if not finishOK then

		return finishWithError(

			"FINISH: "
			..
			safeString(
				finishError
			)

		)

	end


	--==========================================================
	-- LINK
	--==========================================================

	local link =
		finishData
		and
		(
			finishData.downloadUrl
			or
			finishData.url
			or
			finishData.link
		)


	if not link then

		State.Uploading =
			false


		return false,
			"Upload terminou, mas o servidor não retornou o link"

	end


	State.LastUploadLink =
		link


	----------------------------------------------------------
	-- COPIA SOMENTE O LINK
	----------------------------------------------------------

	copyText(
		link
	)


	State.Uploading =
		false


	return true,
		link

end
