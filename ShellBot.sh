#!/bin/bash

#-----------------------------------------------------------------------------------------------------------
#	DATA:				07 de Março de 2017
#	SCRIPT:				ShellBot.sh
#	VERSÃO:				5.0
#	DESENVOLVIDO POR:	Juliano Santos [SHAMAN]
#	PÁGINA:				http://www.shellscriptx.blogspot.com.br
#	FANPAGE:			https://www.facebook.com/shellscriptx
#	GITHUB:				https://github.com/shellscriptx
# 	CONTATO:			shellscriptx@gmail.com
#
#	DESCRIÇÃO:			ShellBot é uma API não-oficial desenvolvida para facilitar a criação de 
#						bots na plataforma TELEGRAM. Constituída por uma coleção de métodos
#						e funções que permitem ao desenvolvedor:
#
#							* Gerenciar grupos, canais e membros.
#							* Enviar mensagens, documentos, músicas, contatos e etc.
#							* Enviar teclados (KeyboardMarkup e InlineKeyboard).
#							* Obter informações sobre membros, arquivos, grupos e canais.
#							* Para mais informações consulte a documentação:
#							  
#							https://github.com/shellscriptx/ShellBot/wiki
#
#						O ShellBot mantém o padrão da nomenclatura dos métodos registrados da
#						API original (Telegram), assim como seus campos e valores. Os métodos
#						requerem parâmetros e argumentos para a chamada e execução. Parâmetros
#						obrigatórios retornam uma mensagem de erro caso o argumento seja omitido.
#						
#	NOTAS:				Desenvolvida na linguagem Shell Script, utilizando o interpretador de 
#						comandos BASH e explorando ao máximo os recursos built-in do mesmo,
#						reduzindo o nível de dependências de pacotes externos.
#-----------------------------------------------------------------------------------------------------------

# Verifica se a API já foi instanciada.
[[ $_SHELLBOT_SH_ ]] && return 1

# Verifica se os pacotes necessários estão instalados.
for _pkg_ in curl jq getopt; do
	# Se estiver ausente, trata o erro e finaliza o script.
	if ! which $_pkg_ &>/dev/null; then
		echo "ShellBot.sh: erro: '$_pkg_' O pacote requerido não está instalado." 1>&2
		exit 1	# Status
	fi
done

# Script que importou a API.
declare -r _BOT_SCRIPT_=$(basename "$0")

# API inicializada.
declare -r _SHELLBOT_SH_=1

# Desabilitar globbing
set -f

# curl parâmetros
declare -r _CURL_OPT_='--silent --request'

# Erros registrados da API (Parâmetros/Argumentos)
declare -r _ERR_TYPE_BOOL_='Tipo incompatível: Suporta somente "true" ou "false".'
declare -r _ERR_TYPE_PARSE_MODE_='Formação inválida: Suporta Somente "markdown" ou "html".'
declare -r _ERR_TYPE_INT_='Tipo incompatível: Suporta somente inteiro.'
declare -r _ERR_TYPE_FLOAT_='Tipo incompatível: Suporta somente float.'
declare -r _ERR_TYPE_POINT_='Máscara inválida: Deve ser “forehead”, “eyes”, “mouth” ou “chin”.'
declare -r _ERR_ACTION_MODE_='Ação inválida: A definição da ação não é suportada.'
declare -r _ERR_PARAM_REQUIRED_='Opção requerida: Verique se o(s) parâmetro(s) ou argumento(s) obrigatório(s) estão presente(s).'
declare -r _ERR_TOKEN_UNAUTHORIZED_='Não autorizado. Verifique se possui permissões para utilizar o token.'
declare -r _ERR_TOKEN_INVALID_='TOKEN inválido: Verique o número do token e tente novamente.'
declare -r _ERR_FUNCTION_NOT_FOUND_='Função inválida: Verique se o nome está correto ou se a função existe.'
declare -r _ERR_BOT_ALREADY_INIT_='Ação não permitida: O bot já foi inicializado.'
declare -r _ERR_FILE_NOT_FOUND_='Arquivo não encontrado: Não foi possível ler o arquivo especificado.'
declare -r _ERR_DIR_WRITE_DENIED_='Não é possível gravar no diretório: Permissão negada.'
declare -r _ERR_DIR_NOT_FOUND_='Não foi possível acessar: Diretório não encontrado.'
declare -r _ERR_FILE_DOWNLOAD_='Não foi possível realizar o download: Arquivo não encontrado.'
declare -r _ERR_FILE_INVALID_ID_='Arquivo não encontrado: ID inválido.'
declare -r _ERR_UNKNOWN_='Erro desconhecido: Ocorreu uma falha inesperada. Reporte o problema ao desenvolvedor.'
declare -r _ERR_SERVICE_NOT_ROOT_='Acesso negado: Requer privilégios de root.'
declare -r _ERR_SERVICE_EXISTS_='Não foi possível criar o serviço: O nome do serviço já existe.'
declare -r _ERR_SERVICE_SYSTEMD_NOT_FOUND_='Erro ao ativar: O sistema não possui suporte ao gerenciamento de serviços "systemd".'
declare -r _ERR_SERVICE_USER_NOT_FOUND_='Usuário não encontrado: A conta de usuário informada é inválida.'

json() { jq "$1" <<< "${*:2}" 2>/dev/null | sed -r '/^"/s/(^"|"$)//g'; }
getObjVal(){ sed -nr 's/^\s+"[a-z_]+":\s+"?(.+[^",])*"?,?$/\1/p' | sed ':a;N;s/\n/|/;ta'; }
json_status(){ [[ $(jq '.ok' <<< "$*") == true ]] && return 0 || return 1; }

flushOffset()
{    
	local first_id last_id cod end jq_obj
	
	# Sem erro
	cod=0
	update_id=0
	
	while [[ $update_id ]]
	do
		# Lê as atualizações do offset atual. É possível listar no máximo 100 objetos por offset.
		if jq_obj=$(ShellBot.getUpdates --limit 100 --offset $(ShellBot.OffsetNext))
		then
			# Lê os IDs das atualizações disponíveis, salva o primeiro e último elemento da lista.
			# Interrompe o laço se não houver mais atualizações.
			unset update_id
			update_id=($(json '.result|.[]|.update_id' $jq_obj))

			first_id=${first_id:-$update_id}
			end=$(ShellBot.OffsetEnd)
			((end > 0)) && last_id=$end
		else
			# Seta o erro e finaliza o laço em caso de falha na chamada do método.
			cod=1
			break
		fi	
	done

	# Retorna '0' se não houver registro.
	# Saída: 0|0
	echo "${first_id:-0}|${last_id:-0}"

	# Desativa a flag
	unset _FLUSH_OFFSET_

	# Status
	return $cod
}    

message_error()
{
	# Variáveis locais
	local err_message err_param assert err_line err_func
	
	# A variável 'BASH_LINENO' é dinâmica e armazena o número da linha onde foi expandida.
	# Quando chamada dentro de um subshell, passa ser instanciada como um array, armazenando diversos
	# valores onde cada índice refere-se a um shell/subshell. As mesmas caracteristicas se aplicam a variável
	# 'FUNCNAME', onde é armazenado o nome da função onde foi chamada.
	err_line=${BASH_LINENO[1]}	# Obtem o número da linha no shell pai.
	err_func=${FUNCNAME[1]}		# Obtem o nome da função no shell pai.
	
	# Lê o tipo de ocorrência do erro.
	# TG - Erro externo, retornado pelo core do telegram
	# API - Erro interno, gerado pela API ShellBot.
	case $1 in
		TG)
			# arquivo json
			err_param="$(json '.error_code' ${*:2})"
			err_message="$(json '.description' ${*:2})"
			;;
		API)
			err_param="${3:--}: ${4:--}"
			err_message="$2"
			assert=1
			;;
	esac

	# Imprime erro
	printf "%s: erro: linha %s: %s: %s: %s\n" "${_BOT_SCRIPT_}" \
												"${err_line:--}" \
												"${err_func:--}" \
												"${err_param:--}" \
												"${err_message:-$_ERR_UNKNOWN_}" 1>&2 

	# Finaliza script/thread em caso de erro interno, caso contrário retorna 1
	[[ $assert ]] && exit 1 || return 1
}

createUnitService()
{
	local service=${1%.*}.service
	local ok='\033[0;32m[OK]\033[0;m'
	local fail='\033[0;31m[FALHA]\033[0;m'
	
	((UID == 0)) || message_error API "$_ERR_SERVICE_NOT_ROOT_"

	# O modo 'service' requer que o sistema de gerenciamento de processos 'systemd'
	# esteja presente para que o Unit target seja linkado ao serviço.
	if ! which systemd &>/dev/null; then
		message_error API "$_ERR_SERVICE_SYSTEMD_NOT_FOUND_"; fi


	# Se o serviço existe.
	test -e /lib/systemd/system/$service && \
	message_error API "$_ERR_SERVICE_EXISTS_" "$service"

	# Gerando as configurações do target.
	cat > /lib/systemd/system/$service << _eof
[Unit]
Description=$1 - (SHELLBOT)
After=network-online.target

[Service]
User=$2
WorkingDirectory=$PWD
ExecStart=/bin/bash $1
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=/bin/kill -KILL \$MAINPID
KillMode=process
Restart=on-failure
RestartPreventExitStatus=255
Type=simple

[Install]
WantedBy=multi-user.target
_eof

	[[ $? -eq 0 ]] && {	
		
		printf '%s foi criado com sucesso !!\n' $service	
	
		ln -s /lib/systemd/system/$service /etc/systemd/system/$service
		systemctl daemon-reload
		
		echo -n "Habilitando..."
 		systemctl enable $service &>/dev/null && echo -e $ok || \
		{ echo -e $fail; message_error API "$_ERR_UNKNOWN_"; }

		sed -i -r '/^[^#]*ShellBot.init\s/s/\s--?(s(ervice)?|u(ser)?\s+\w+)\b//g' "$1"

		echo -n "Iniciando..."
		systemctl start $service && echo -e $ok || echo -e $fail
		systemctl status $service

		echo -e "\nUso: sudo systemctl $service {start|stop|restart|reload|status}"
	
	} || message_error API "$_ERR_UNKNOWN_"

	exit 0
}

# Inicializa o bot, definindo sua API e _TOKEN_.
ShellBot.init()
{
	# Verifica se o bot já foi inicializado.
	[[ $_SHELLBOT_INIT_ ]] && message_error API "$_ERR_BOT_ALREADY_INIT_"
	
	local enable_service user_unit

	local param=$(getopt --name "$FUNCNAME" \
						 --options 't:mfsu:' \
						 --longoptions 'token:,
										monitor,
										flush,
										service,
										user:' \
    					 -- "$@")
    
    # Define os parâmetros posicionais
    eval set -- "$param"
   
	while :
    do
    	case $1 in
    		-t|--token)
    			[[ $2 =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]] || message_error API "$_ERR_TOKEN_INVALID_" "$1" "$2"
    			declare -gr _TOKEN_="$2"												# TOKEN
    			declare -gr _API_TELEGRAM_="https://api.telegram.org/bot$_TOKEN_"		# API
    			shift 2
   				;;
   			-m|--monitor)
				# Ativa modo monitor
   				declare -gr _BOT_MONITOR_=1
   				shift
   				;;
			-f|--flush)
				# Define a FLAG flush para o método 'ShellBot.getUpdates'. Se ativada, faz com que
				# o método obtenha somente as atualizações disponíveis, ignorando a extração dos
				# objetos JSON e a inicialização das variáveis.
				declare -x _FLUSH_OFFSET_=1
				shift
				;;
			-s|--service)
				enable_service=1
				shift
				;;
			-u|--user)
				if ! id "$2" &>/dev/null; then
					message_error API "$_ERR_SERVICE_USER_NOT_FOUND_" "[-u, --user]" "$2"; fi

				user_unit="$2"
				shift 2
				;;				
   			--)
   				shift
   				break
   				;;
   		esac
   	done
  
   	# Parâmetro obrigatório.	
   	[[ $_TOKEN_ ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-t, --token]"
	[[ $user_unit && ! $enable_service ]] && message_error API "$_ERR_PARAM_REQUIRED_" "[-s, --service]" 
	[[ $enable_service ]] && createUnitService "$_BOT_SCRIPT_" "${user_unit:-$USER}"
		   
    # Um método simples para testar o token de autenticação do seu bot. 
    # Não requer parâmetros. Retorna informações básicas sobre o bot em forma de um objeto Usuário.
    ShellBot.getMe()
    {
		local jq_obj

    	# Chama o método getMe passando o endereço da API, seguido do nome do método.
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.})
    	
    	# Verifica o status de retorno do método
    	json_status $jq_obj && {
    		# Retorna as informações armazenadas em "result".
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	return $?
    }

   	_BOT_INFO_=$(ShellBot.getMe 2>/dev/null) || message_error API "$_ERR_TOKEN_UNAUTHORIZED_" '[-t, --token]'
   	
   	# Define o delimitador entre os campos.
   	# Inicializa um array somente leitura contendo as informações do bot.
   	IFSbkp=$IFS; IFS='|'
   	declare -gr _BOT_INFO_=($_BOT_INFO_)
   	IFS=$IFSbkp
  
	# Bot inicializado
	declare -gr _SHELLBOT_INIT_=1 

    # SHELLBOT (FUNÇÕES)
	# Inicializa as funções para chamadas aos métodos da API do telegram.
	ShellBot.ListUpdates(){ echo ${!update_id[@]}; }
	ShellBot.TotalUpdates(){ echo ${#update_id[@]}; }
	ShellBot.OffsetEnd(){ local -i offset=${update_id[@]: -1}; echo $offset; }
	ShellBot.OffsetNext(){ echo $(($(ShellBot.OffsetEnd)+1)); }
   	
	ShellBot.token() { echo "${_TOKEN_}"; }
	ShellBot.id() { echo "${_BOT_INFO_[0]}"; }
	ShellBot.first_name() { echo "${_BOT_INFO_[2]}"; }
	ShellBot.username() { echo "${_BOT_INFO_[3]}"; }
   
    ShellBot.regHandleFunction()
    {
    	local function callback_data handle args
    
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'f:a:d:' \
							 --longoptions 'function:,
											args:,
											callback_data:' \
							 -- "$@")
    
    	eval set -- "$param"
    		
    	while :
    	do
    		case $1 in
    			-f|--function)
    				# Verifica se a função especificada existe.
    				if ! declare -fp $2 &>/dev/null; then
    					message_error API "$_ERR_FUNCTION_NOT_FOUND_" "$1" "$2"
    					return 1
    				fi
    				function="$2"
    				shift 2
    				;;
    			-a|--args)
    				args="$2"
    				shift 2
    				;;
    			-d|--callback_data)
    				callback_data="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $function ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-f, --function]"
    	[[ $callback_data ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-d, --callback_data]"
    
    	# Testa se o indentificador armazenado em handle já existe. Caso já exista, repete
    	# o procedimento até que um handle válido seja gerado; Evitando sobreescrever handle's existentes.
    	until ! declare -fp $handle &>/dev/null; do
			handle=$(mktemp --dry-run HandleID:XXXXXXXXXXXXXXX)
    	done
    
    	# Cria a função com o nome gerado e adiciona a chamada com os argumentos especificados.
    	# Anexa o novo handle a lista no índice associativo definindo em callback_data	
    	function="$handle(){ $function $args; }"
    	eval "$function"
    	
    	declare -Ag _reg_func_handle_list_
    	_reg_func_handle_list_[$callback_data]+="$handle "
    
    	return 0
    }
    
    ShellBot.watchHandle()
    {
    	local 	callback_data func_handle \
    			param=$(getopt --name "$FUNCNAME" \
								--options 'd' \
								--longoptions 'callback_data' \
								-- "$@")
    
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-d|--callback_data)
    				shift 2
    				callback_data="$1"
    				;;
    			*)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# O parâmetro callback_data é parcial, ou seja, Se o handle for válido, os elementos
    	# serão listados. Caso contrário a função é finalizada.
    	[[ $callback_data ]] || return 1
    
    	# Lista todos os handles no índice callback_data  e executa-os
    	# consecutivamente. A ordem de execução das funções é determinada
    	# pela ordem de declaração.
    	for func_handle in ${_reg_func_handle_list_[$callback_data]}; do 
    		$func_handle; done	# executa
    
    	# retorno
    	return 0
    }
    
    ShellBot.getWebhookInfo()
    {
    	# Variável local
    	local jq_obj
	
    	# Chama o método getMe passando o endereço da API, seguido do nome do método.
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.})
    	
    	# Verifica o status de retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    	
    	return $?
    }
    
    ShellBot.deleteWebhook()
    {
    	# Variável local
    	local jq_obj
	
    	# Chama o método getMe passando o endereço da API, seguido do nome do método.
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.})
    	
    	# Verifica o status de retorno do método
    	json_status $jq_obj || message_error TG $jq_obj
    	
    	return $?
    }
    
    ShellBot.setWebhook()
    {
    	local url certificate max_connections allowed_updates jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'u:c:m:a:' \
							 --longoptions 'url:, 
    										certificate:,
    										max_connections:,
    										allowed_updates:' \
    						 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-u|--url)
    				url="$2"
    				shift 2
    				;;
    			-c|--certificate)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				certificate="$2"
    				shift 2
    				;;
    			-m|--max_connections)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				max_connections="$2"
    				shift 2
    				;;
    			-a|--allowed_updates)
    				allowed_updates="$2"
    				shift 2
    				;;
    			--)
    				shift 
    				break
    				;;
    		esac
    	done
    	
    	[[ $url ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-u, --url]"
    
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${url:+-d url="$url"} \
    								 ${certificate:+-d certificate="$certificate"} \
    								 ${max_connections:+-d max_connections="$max_connections"} \
    								 ${allowed_updates:+-d allowed_updates="$allowed_updates"})
    
    	# Testa o retorno do método.
    	json_status $jq_obj || message_error TG $jq_obj
    	
    	# Status
    	return $?
    }	
    
    ShellBot.setChatPhoto()
    {
    	local chat_id photo jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:p:' \
							 --longoptions 'chat_id:,photo:' \
							 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-p|--photo)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				photo="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	[[ $photo ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-p, --photo"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${photo:+-F photo="$photo"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    		
    	# Status
    	return $?
    }
    
    ShellBot.deleteChatPhoto()
    {
    	local chat_id jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:' \
							 --longoptions 'chat_id:' \
							 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    		
    	# Status
    	return $?
    
    }
    
    ShellBot.setChatTitle()
    {
    	
    	local chat_id title jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:t:' \
							 --longoptions 'chat_id:,title:' \
							 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-t|--title)
    				title="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	[[ $title ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-t, --title"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${title:+-d title="$title"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    		
    	# Status
    	return $?
    }
    
    
    ShellBot.setChatDescription()
    {
    	
    	local chat_id description jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:d:' \
							 --longoptions 'chat_id:,description:' \
							 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-d|--description)
    				description="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	[[ $description ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-d, --description"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${description:+-d description="$description"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    		
    	# Status
    	return $?
    }
    
    ShellBot.pinChatMessage()
    {
    	
    	local chat_id message_id disable_notification jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:m:n:' \
							 --longoptions 'chat_id:,
											message_id:,
    										disable_notification:' \
    						 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-m|--message_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				message_id="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;	
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	[[ $message_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-m, --message_id"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${message_id:+-d message_id="$message_id"} \
    								 ${disable_notification:+-d disable_notification="$disable_notification"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    		
    	# Status
    	return $?
    }
    
    ShellBot.unpinChatMessage()
    {
    	local chat_id jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:' \
							 --longoptions 'chat_id:' \
							 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    		
    	# Status
    	return $?
    }
    
    ShellBot.restrictChatMember()
    {
    	local	chat_id user_id until_date can_send_messages \
    			can_send_media_messages can_send_other_messages \
    			can_add_web_page_previews jq_obj
    
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:u:d:s:m:o:w:' \
    						 --longoptions 'chat_id:,
    										user_id:,
    										until_date:,
    										can_send_messages:,
    										can_send_media_messages:,
    										can_send_other_messages:,
    										can_add_web_page_previews:' \
							 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-u|--user_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				user_id="$2"
    				shift 2
    				;;
    			-d|--until_date)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				until_date="$2"
    				shift 2
    				;;
    			-s|--can_send_messages)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_send_messages="$2"
    				shift 2
    				;;
    			-m|--can_send_media_messages)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_send_media_messages="$2"
    				shift 2
    				;;
    			-o|--can_send_other_messages)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_send_other_messages="$2"
    				shift 2
    				;;
    			-w|--can_add_web_page_previews)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_add_web_page_previews="$2"
    				shift 2
    				;;				
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --user_id"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${user_id:+-d user_id="$user_id"} \
    								 ${until_date_:+-d until_date="$until_date"} \
    								 ${can_send_messages:+-d can_send_messages="$can_send_messages"} \
    								 ${can_send_media_messages:+-d can_send_media_messages="$can_send_media_messages"} \
    								 ${can_send_other_messages:+-d can_send_other_messages="$can_send_other_messages"} \
    								 ${can_add_web_page_previews:+-d can_add_web_page_previews="$can_add_web_page_previews"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    		
    	# Status
    	return $?
    	
    }
    
    
    ShellBot.promoteChatMember()
    {
    	local	chat_id user_id can_change_info can_post_messages \
    			can_edit_messages can_delete_messages can_invite_users \
    			can_restrict_members can_pin_messages can_promote_members \
				jq_obj
    
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:u:i:p:e:d:v:r:f:m:' \
							 --longoptions 'chat_id:,
    										user_id:,
    										can_change_info:,
    										can_post_messages:,
    										can_edit_messages:,
    										can_delete_messages:,
    										can_invite_users:,
    										can_restrict_members:,
    										can_pin_messages:,
    										can_promote_members:' \
							 -- "$@")
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-u|--user_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				user_id="$2"
    				shift 2
    				;;
    			-i|--can_change_info)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_change_info="$2"
    				shift 2
    				;;
    			-p|--can_post_messages)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_post_messages="$2"
    				shift 2
    				;;
    			-e|--can_edit_messages)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_edit_messages="$2"
    				shift 2
    				;;
    			-d|--can_delete_messages)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_delete_messages="$2"
    				shift 2
    				;;
    			-v|--can_invite_users)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_invite_users="$2"
    				shift 2
    				;;
    			-r|--can_restrict_members)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_restrict_members="$2"
    				shift 2
    				;;
    			-f|--can_pin_messages)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_pin_messages="$2"
    				shift 2
    				;;	
    			-m|--can_promote_members)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				can_promote_members="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --user_id"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${user_id:+-d user_id="$user_id"} \
    								 ${can_change_info:+-d can_change_info="$can_change_info"} \
    								 ${can_post_messages:+-d can_post_messages="$can_post_messages"} \
    								 ${can_edit_messages:+-d can_edit_messages="$can_edit_messages"} \
    								 ${can_delete_messages:+-d can_delete_messages="$can_delete_messages"} \
    								 ${can_invite_users:+-d can_invite_users="$can_invite_users"} \
    								 ${can_restrict_members:+-d can_restrict_members="$can_restrict_members"} \
    								 ${can_pin_messages:+-d can_pin_messages="$can_pin_messages"} \
    								 ${can_promote_members:+-d can_promote_members="$can_promote_members"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    		
    	# Status
    	return $?
    }
    
    ShellBot.exportChatInviteLink()
    {
    	local chat_id jq_obj
    
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:' \
							 --longoptions 'chat_id:' \
							 -- "$@")
    	
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"})
    	
    	# Testa o retorno do método.
    	json_status $jq_obj && {
    		json '.result' $jq_obj
    	} || message_error TG $jq_obj
    		
    	# Status
    	return $?
    }
    
    ShellBot.sendVideoNote()
    {
    	local chat_id video_note duration length disable_notification \
    			reply_to_message_id reply_markup jq_obj
    
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:v:t:l:n:r:m:' \
							 --longoptions 'chat_id:,
    										video_note:,
    										duration:,
    										length:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-v|--video_note)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				video_note="$2"
    				shift 2
    				;;
    			-t|--duration)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				duration="$2"
    				shift 2
    				;;
    			-l|--length)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				length="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-m|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --chat_id"
    	[[ $video_note ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-v, --video_note"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${video_note:+-F video_note="$video_note"} \
    								 ${duration:+-F duration="$duration"} \
    								 ${length:+-F length="$length"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Testa o retorno do método.
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    	
    	# Status
    	return $?
    }
    
    
    ShellBot.InlineKeyboardButton()
    {
        local 	button line text url callback_data \
                switch_inline_query switch_inline_query_current_chat \
    			delm
    
        local param=$(getopt --name "$FUNCNAME" \
							 --options 'b:l:t:u:c:q:s:' \
							 --longoptions 'button:,
											line:,
											text:,
											url:,
											callback_data:,
											switch_inline_query:,
											switch_inline_query_chat:' \
							 -- "$@")
    
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-b|--button)
    				# Ponteiro que recebe o endereço de "button" com as definições
    				# da configuração do botão inserido.
    				button="$2"
    				shift 2
    				;;
    			-l|--line)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				line="$2"
    				shift 2
    				;;
    			-t|--text)
    				text="$2"
    				shift 2
    				;;
    			-u|--url)
    				url="$2"
    				shift 2
    				;;
    			-c|--callback_data)
    				callback_data="$2"
    				shift 2
    				;;
    			-q|--switch_inline_query)
    				switch_inline_query="$2"
    				shift 2
    				;;
    			-s|--switch_inline_query_current_chat)
    				switch_inline_query_current_chat="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    
    	[[ $button ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-b, --button"
    	[[ $text ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-t, --text"
    	[[ $callback_data ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --callback_data"
    	[[ $line ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-l, --line"
    	
    	# Inicializa a variável armazenada em button, definindo seu
    	# escopo como global, tornando-a visível em todo o projeto (source)
    	# O ponteiro button recebe o endereço do botão armazenado.
    	declare -g $button
    	declare -n button	# Ponteiro
    	
    	# Abre o array para receber o novo objeto
    	button[$line]="${button[$line]#[}"
    	button[$line]="${button[$line]%]}"
    
    	# Verifica se já existe um botão na linha especificada.
    	[[ ${button[$line]} ]] && delm=','
    
    	# Salva as configurações do botão.
    	#
    	# Obrigatório: text, callback_data 
    	# Opcional: url, switch_inline_query, switch_inline_query_current_chat
    	button[$line]+="${delm}{ 
    					\"text\":\"${text}\",
						\"callback_data\":\"${callback_data}\"
						${url:+,\"url\":\"${url}\"}
						${switch_inline_query:+,\"switch_inline_query\":\"${switch_inline_query}\"}
						${switch_inline_query_current_chat:+,\"switch_inline_query_current_chat\":\"${switch_inline_query_current_chat}\"}
						}" || return 1	# Erro ao salvar o botão. 
    	
    	# Fecha o array
    	button[$line]="${button[$line]/#/[}"
    	button[$line]="${button[$line]/%/]}"
    
    	# retorno
    	return 0
    }
    
    ShellBot.InlineKeyboardMarkup()
    {
    	local 	button temp_kb 
        local param=$(getopt --name "$FUNCNAME" \
							 --options 'b:' \
							 --longoptions 'button:' \
							 -- "$@")
    
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-b|--button)
    				# Ponteiro que recebe o endereço da variável "teclado" com as definições
    				# de configuração do botão inserido.
    				button="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $button ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-b, --button"
    	
    	# Ponteiro
    	declare -n button
    
    	# Salva todos elementos do array do teclado, convertendo-o em uma variável de índice 0.
    	# Cria-se uma estrutura do tipo 'inline_keyboard' e anexa os botões e fecha a estrutura.
    	# O ponteiro matriz é limpo para receber a nova estrutura contendo o layout do objeto.
    	# O tipo 'inline_keyboard' é definido, adicionando os botões separando-os pelo delimitador
    	# ',' vírgula. A posição dos botões é determinada pelo índice da linha na inicilização.
    	#
    	# Exemplo:
    	#
    	#	Linha					array
    	#
    	#	 1		[inline_botao1] [inline_botao2] [inline_botao3]
    	#	 2				[inline_botao4] [inline_botao5]
    	#	 3			            [inline_botao7]
    	
    	keyboard="${button[@]}" || return 1
    	
    	# Cria estrutura do teclado
    	keyboard="${keyboard/#/{\"inline_keyboard\":[}"
    	keyboard="${keyboard//]/],}"					
    	keyboard="${keyboard%,}"						
    	keyboard="${keyboard/%/]\}}"					
    
    	# Retorna a estrutura	
    	echo $keyboard
    
    	# status
    	return 0
    }
    
    ShellBot.answerCallbackQuery()
    {
    	local callback_query_id text show_alert url cache_time jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:t:s:u:e:' \
    						 --longoptions 'callback_query_id:,
    										text:,
    										show_alert:,
    										url:,
    										cache_time:' \
    						 -- "$@")
    
    
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--callback_query_id)
    				callback_query_id="$2"
    				shift 2
    				;;
    			-t|--text)
    				text="$2"
    				shift 2
    				;;
    			-s|--show_alert)
    				# boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				show_alert="$2"
    				shift 2
    				;;
    			-u|--url)
    				url="$2"
    				shift 2
    				;;
    			-e|--cache_time)
    				# inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				cache_time="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $callback_query_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-c, --callback_query_id"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${callback_query_id:+-d callback_query_id="$callback_query_id"} \
    								 ${text:+-d text="$text"} \
    								 ${show_alert:+-d show_alert="$show_alert"} \
    								 ${url:+-d url="$url"} \
    								 ${cache_time:+-d cache_time="$cache_time"})
    
    	json_status $jq_obj || message_error TG $jq_obj
    
    	return $?
    }
    
    # Cria objeto que representa um teclado personalizado com opções de resposta
    ShellBot.ReplyKeyboardMarkup()
    {
    	# Variáveis locais
    	local 	button resize_keyboard on_time_keyboard selective
    	
    	# Lê os parâmetros da função.
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'b:r:t:s:' \
    						 --longoptions 'button:,
    										resize_keyboard:,
    										one_time_keyboard:,
    										selective:' \
    						 -- "$@")
    	
    	# Transforma os parâmetros da função em parâmetros posicionais
    	#
    	# Exemplo:
    	#	--param1 arg1 --param2 arg2 --param3 arg3 ...
    	# 		$1			  $2			$3
    	eval set -- "$param"
    	
    	# Aguarda leitura dos parâmetros
    	while :
    	do
    		# Lê o parâmetro da primeira posição "$1"; Se for um parâmetro válido,
    		# salva o valor do argumento na posição '$2' e desloca duas posições a esquerda (shift 2); Repete o processo
    		# até que o valor de '$1' seja igual '--' e finaliza o loop.
    		case $1 in
    			-b|--button)
    				button="$2"
    				shift 2
    				;;
    			-r|--resize_keyboard)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				resize_keyboard="$2"
    				shift 2
    				;;
    			-t|--one_time_keyboard)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				on_time_keyboard="$2"
    				shift 2
    				;;
    			-s|--selective)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				selective="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Imprime mensagem de erro se o parâmetro obrigatório for omitido.
    	[[ $button ]] || message_error API "$_ERR_PARAM_REQUIRED_" "-b, --button"
    
    	# Ponteiro	
    	declare -n button
    
    	# Constroi a estrutura dos objetos + array keyboard, define os valores e salva as configurações.
    	# Por padrão todos os valores são 'false', até que seja definido.
    	cat << _EOF
{"keyboard":$button,
"resize_keyboard":${resize_keyboard:-false},
"one_time_keyboard":${on_time_keyboard:-false},
"selective": ${selective:-false}}
_EOF
    
    	# status
    	return 0
    }
    
    # Envia mensagens 
    ShellBot.sendMessage()
    {
    	# Variáveis locais 
    	local chat_id text parse_mode disable_web_page_preview disable_notification reply_to_message_id reply_markup jq_obj
    	
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:t:p:w:n:r:k:' \
							 --longoptions 'chat_id:,
    										text:,
    										parse_mode:,
    										disable_web_page_preview:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-t|--text)
    				text="$2"
    				shift 2
    				;;
    			-p|--parse_mode)
    				# Tipo: "markdown" ou "html"
    				[[ "$2" =~ ^(markdown|html)$ ]] || message_error API "$_ERR_TYPE_PARSE_MODE_" "$1" "$2"
    				parse_mode="$2"
    				shift 2
    				;;
    			-w|--disable_web_page_preview)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_web_page_preview="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    
    	# Parâmetros obrigatórios.
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $text ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-t, --text]"
    
    	# Chama o método da API, utilizando o comando request especificado; Os parâmetros 
    	# e valores são passados no form e lidos pelo método. O retorno do método é redirecionado para o arquivo 'update.json'.
    	# Variáveis com valores nulos são ignoradas e consequentemente os respectivos parâmetros omitidos.
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${text:+-d text="$text"} \
    								 ${parse_mode:+-d parse_mode="$parse_mode"} \
    								 ${disable_web_page_preview:+-d disable_web_page_preview="$disable_web_page_preview"} \
    								 ${disable_notification:+-d disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-d reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-d reply_markup="$reply_markup"})
   
    	# Testa o retorno do método.
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    	
    	# Status
    	return $?
    }
    
    # Função para reencaminhar mensagens de qualquer tipo.
    ShellBot.forwardMessage()
    {
    	# Variáveis locais
    	local chat_id form_chat_id disable_notification message_id jq_obj
    	
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:f:n:m:' \
    						 --longoptions 'chat_id:,
    										from_chat_id:,
    										disable_notification:,
    										message_id:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-f|--from_chat_id)
    				from_chat_id="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-m|--message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				message_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parâmetros obrigatórios.
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $from_chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-f, --from_chat_id]"
    	[[ $message_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-m, --message_id]"
    
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    		 						 ${from_chat_id:+-d from_chat_id="$from_chat_id"} \
    								 ${disable_notification:+-d disable_notification="$disable_notification"} \
    								 ${message_id:+-d message_id="$message_id"})
    	
    	# Retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# status
    	return $?
    }
    
    # Utilize essa função para enviar fotos.
    ShellBot.sendPhoto()
    {
    	# Variáveis locais
    	local chat_id photo caption disable_notification reply_to_message_id reply_markup jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:p:t:n:r:k:' \
    						 --longoptions 'chat_id:, 
    										photo:,
    										caption:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-p|--photo)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				photo="$2"
    				shift 2
    				;;
    			-t|--caption)
    				# Limite máximo de caracteres: 200
    				caption="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parâmetros obrigatórios
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $photo ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-p, --photo]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${photo:+-F photo="$photo"} \
    								 ${caption:+-F caption="$caption"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    	
    	# Retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    }
    
    # Utilize essa função para enviar arquivos de audio.
    ShellBot.sendAudio()
    {
    	# Variáveis locais
    	local chat_id audio caption duration performer title disable_notification reply_to_message_id reply_markup jq_obj
    	
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:a:t:d:e:i:n:r:k' \
    						 --longoptions 'chat_id:,
    										audio:,
    										caption:,
    										duration:,
    										performer:,
    										title:,
    										disable_notification:,
    										reply_to_message_id:,	
    										reply_markup:' \
    						 -- "$@")
    
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-a|--audio)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				audio="$2"
    				shift 2
    				;;
    			-t|--caption)
    				caption="$2"
    				shift 2
    				;;
    			-d|--duration)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				duration="$2"
    				shift 2
    				;;
    			-e|--performer)
    				performer="$2"
    				shift 2
    				;;
    			-i|--title)
    				title="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parâmetros obrigatórios
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $audio ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-a, --audio]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${audio:+-F audio="$audio"} \
    								 ${caption:+-F caption="$caption"} \
    								 ${duration:+-F duration="$duration"} \
    								 ${performer:+-F performer="$performer"} \
    								 ${title:+-F title="$title"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    		
    }
    
    # Utilize essa função para enviar documentos.
    ShellBot.sendDocument()
    {
    	# Variáveis locais
    	local chat_id document caption disable_notification reply_to_message_id reply_markup jq_obj
    	
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:d:t:n:r:k:' \
    						 --longoptions 'chat_id:,
											document:,
    										caption:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-d|--document)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				document="$2"
    				shift 2
    				;;
    			-t|--caption)
    				caption="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_MARKUP="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parâmetros obrigatórios
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $document ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-d, --document]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${document:+-F document="$document"} \
    								 ${caption:+-F caption="$caption"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    	
    }
    
    # Utilize essa função para enviat stickers
    ShellBot.sendSticker()
    {
    	# Variáveis locais
    	local chat_id sticker disable_notification reply_to_message_id reply_markup jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:s:n:r:k:' \
    						 --longoptions 'chat_id:,
    										sticker:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-s|--sticker)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				sticker="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parâmetros obrigatórios
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $sticker ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-s, --sticker]"
    
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${sticker:+-F sticker="$sticker"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Testa o retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    }
   
	ShellBot.getStickerSet()
	{
		local name jq_obj
		
		local param=$(getopt --name "$FUNCNAME" \
							 --options 'n:' \
							 --longoptions 'name:' \
							 -- "$@")
		
		# parâmetros posicionais
		eval set -- "$param"

		while :
		do
			case $1 in
				-n|--name)
					name="$2"
					shift 2
					;;
				--)
					shift
					break
					;;
			esac
		done
    	
		[[ $name ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-n, --name]"
    	
		jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${name:+-d name="$name"})
    	
		# Testa o retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
	} 
	
	ShellBot.uploadStickerFile()
	{
		local user_id png_sticker jq_obj
		
		local param=$(getopt --name "$FUNCNAME" \
							 --options 'u:s:' \
							 --longoptions 'user_id:,
											png_sticker:' \
							 -- "$@")
		
		eval set -- "$param"
		
		while :
		do
			case $1 in
				-u|--user_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
					user_id="$2"
					shift 2
					;;
				-s|--png_sticker)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
					png_sticker="$2"
					shift 2
					;;
				--)
					shift
					break
					;;
				esac
		done

		[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-u, --user_id]"
		[[ $png_sticker ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-s, --png_sticker]"
    	
		jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${user_id:+-F user_id="$user_id"} \
									 ${png_sticker:+-F png_sticker="$png_sticker"})
    	
		# Testa o retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
					
	}

	ShellBot.setStickerPositionInSet()
	{
		local sticker position jq_obj

		local param=$(getopt --name "$FUNCNAME" \
							 --options 's:p:' \
							 --longoptions 'sticker:,
											position:' \
							 -- "$@")
		
		eval set -- "$param"

		while :
		do
			case $1 in
				-s|--sticker)
					sticker="$2"
					shift 2
					;;
				-p|--position)
					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
					position="$2"
					shift 2
					;;
				--)
					shift
					break
					;;
			esac
		done
		
		[[ $sticker ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-s, --sticker]"
		[[ $position ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-p, --position]"
    	
		jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${sticker:+-d sticker="$sticker"} \
									 ${position:+-d position="$position"})
    	
		# Testa o retorno do método
    	json_status $jq_obj || message_error TG $jq_obj
    	
		# Status
    	return $?
				
	}
	
	ShellBot.deleteStickerFromSet()
	{
		local sticker jq_obj

		local param=$(getopt --name "$FUNCNAME" \
							 --options 's:' \
							 --longoptions 'sticker:' \
							 -- "$@")
		
		eval set -- "$param"

		while :
		do
			case $1 in
				-s|--sticker)
					sticker="$2"
					shift 2
					;;
				--)
					shift
					break
					;;
			esac
		done
		
		[[ $sticker ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-s, --sticker]"
    	
		jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${sticker:+-d sticker="$sticker"})
    	
		# Testa o retorno do método
    	json_status $jq_obj || message_error TG $jq_obj
    	
		# Status
    	return $?
				
	}
	
	ShellBot.stickerMaskPosition()
	{

		local point x_shift y_shift scale zoom
		
		local param=$(getopt --name "$FUNCNAME" \
							 --options 'p:x:y:s:z:' \
							 --longoptions 'point:,
											x_shift:,
											y_shift:,
											scale:,
											zoom:' \
							 -- "$@")

		eval set -- "$param"
		
		while :
		do
			case $1 in
				-p|--point)
					[[ "$2" =~ ^(forehead|eyes|mouth|chin)$ ]] || message_error API "$_ERR_TYPE_POINT_" "$1" "$2"
					point="$2"
					shift 2
					;;
				-x|--x_shift)
					[[ "$2" =~ ^-?[0-9]+\.[0-9]+$ ]] || message_error API "$_ERR_TYPE_FLOAT_" "$1" "$2"
					x_shift="$2"
					shift 2
					;;
				-y|--y_shift)
					[[ "$2" =~ ^-?[0-9]+\.[0-9]+$ ]] || message_error API "$_ERR_TYPE_FLOAT_" "$1" "$2"
					y_shift="$2"
					shift 2
					;;
				-s|--scale)
					[[ "$2" =~ ^[0-9]+\.[0-9]+$ ]] || message_error API "$_ERR_TYPE_FLOAT_" "$1" "$2"
					scale="$2"
					shift 2
					;;
				-z|--zoom)
					[[ "$2" =~ ^[0-9]+\.[0-9]+$ ]] || message_error API "$_ERR_TYPE_FLOAT_" "$1" "$2"
					zoom="$2"
					shift 2
					;;
				--)
					shift
					break
					;;
			esac
		done
		
		[[ $point ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-p, --point]"
		[[ $x_shift ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-x, --x_shift]"
		[[ $y_shift ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-y, --y_shift]"
		[[ $scale ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-s, --scale]"
		[[ $zoom ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-z, --zoom]"
		
		cat << _EOF
{ "point": "$point", "x_shift": $x_shift, "y_shift": $y_shift, "scale": $scale, "zoom": $zoom }
_EOF

	return 0

	}

	ShellBot.createNewStickerSet()
	{
		local user_id name title png_sticker emojis contains_masks mask_position jq_obj
		
		local param=$(getopt --name "$FUNCNAME" \
							 --options 'u:n:t:s:e:c:m:' \
							 --longoptions 'user_id:,
											name:,
											title:,
											png_sticker:,
											emojis:,
											contains_mask:,
											mask_position:' \
							 -- "$@")

		eval set -- "$param"
		
		while :
		do
			case $1 in
				-u|--user_id)
					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
					user_id="$2"
					shift 2
					;;
				-n|--name)
					name="$2"
					shift 2
					;;
				-t|--title)
					title="$2"
					shift 2
					;;
				-s|--png_sticker)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
					png_sticker="$2"
					shift 2
					;;
				-e|--emojis)
					emojis="$2"
					shift 2
					;;
				-c|--contains_masks)
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
					contains_masks="$2"
					shift 2
					;;
				-m|--mask_position)
					mask_position="$2"
					shift 2
					;;
				--)
					shift
					break
					;;
			esac
		done
		
		[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-u, --user_id]"
		[[ $name ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-n, --name]"
		[[ $title ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-t, --title]"
		[[ $png_sticker ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-s, --png_sticker]"
		[[ $emojis ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-e, --emojis]"
	
		jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${user_id:+-F user_id="$user_id"} \
									 ${name:+-F name="$name"} \
									 ${title:+-F title="$title"} \
									 ${png_sticker:+-F png_sticker="$png_sticker"} \
									 ${emojis:+-F emojis="$emojis"} \
									 ${contains_masks:+-F contains_masks="$contains_masks"} \
									 ${mask_position:+-F mask_position="$mask_position"})
    	
		# Testa o retorno do método
    	json_status $jq_obj || message_error TG $jq_obj
    	
		# Status
    	return $?
			
	}
	
	ShellBot.addStickerToSet()
	{
		local user_id name png_sticker emojis mask_position jq_obj
		
		local param=$(getopt --name "$FUNCNAME" \
							 --options 'u:n:s:e:m:' \
							 --longoptions 'user_id:,
											name:,
											png_sticker:,
											emojis:,
											mask_position:' \
							 -- "$@")

		eval set -- "$param"
		
		while :
		do
			case $1 in
				-u|--user_id)
					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
					user_id="$2"
					shift 2
					;;
				-n|--name)
					name="$2"
					shift 2
					;;
				-s|--png_sticker)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
					png_sticker="$2"
					shift 2
					;;
				-e|--emojis)
					emojis="$2"
					shift 2
					;;
				-m|--mask_position)
					mask_position="$2"
					shift 2
					;;
				--)
					shift
					break
					;;
			esac
		done
		
		[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-u, --user_id]"
		[[ $name ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-n, --name]"
		[[ $png_sticker ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-s, --png_sticker]"
		[[ $emojis ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-e, --emojis]"
	
		jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${user_id:+-F user_id="$user_id"} \
									 ${name:+-F name="$name"} \
									 ${png_sticker:+-F png_sticker="$png_sticker"} \
									 ${emojis:+-F emojis="$emojis"} \
									 ${mask_position:+-F mask_position="$mask_position"})
    	
		# Testa o retorno do método
    	json_status $jq_obj || message_error TG $jq_obj
    	
		# Status
    	return $?
			
	}

    # Função para enviar arquivos de vídeo.
    ShellBot.sendVideo()
    {
    	# Variáveis locais
    	local chat_id video duration width height caption disable_notification reply_to_message_id reply_markup jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:v:d:w:h:t:n:r:k:' \
							 --longoptions 'chat_id:,
    										video:,
    										duration:,
    										width:,
    										height:,
    										caption:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-v|--video)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				video="$2"
    				shift 2
    				;;
    			-d|--duration)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				duration="$2"
    				shift 2
    				;;
    			-w|--width)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				width="$2"
    				shift 2
    				;;
    			-h|--height)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				height="$2"
    				shift 2
    				;;
    			-t|--caption)
    				caption="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parâmetros obrigatórios.
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $video ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-v, --video]"
    
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${video:+-F video="$video"} \
    								 ${duration:+-F duration="$duration"} \
    								 ${width:+-F width="$width"} \
    								 ${height:+-F height="$height"} \
    								 ${caption:+-F caption="$caption"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Testa o retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    	
    }
    
    # Função para enviar audio.
    ShellBot.sendVoice()
    {
    	# Variáveis locais
    	local chat_id voice caption duration disable_notification reply_to_message_id reply_markup jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:v:t:d:n:r:k:' \
    						 --longoptions 'chat_id:,
    										voice:,
    										caption:,
    										duration:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-v|--voice)
					[[ $2 =~ ^@ && ! -f ${2#@} ]] && message_error API "$_ERR_FILE_NOT_FOUND_" "$1" "$2"
    				voice="$2"
    				shift 2
    				;;
    			-t|--caption)
    				caption="$2"
    				shift 2
    				;;
    			-d|--duration)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				duration="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    		esac
    	done
    	
    	# Parâmetros obrigatórios.
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $voice ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-v, --voice]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${voice:+-F voice="$voice"} \
    								 ${caption:+-F caption="$caption"} \
    								 ${duration:+-F duration="$duration"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Testa o retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    	
    }
    
    # Função utilizada para enviar uma localidade utilizando coordenadas de latitude e longitude.
    ShellBot.sendLocation()
    {
    	# Variáveis locais
    	local chat_id latitude longitude disable_notification reply_to_message_id reply_markup jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:l:g:n:r:k:' \
    						 --longoptions 'chat_id:,
    										latitude:,
    										longitude:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-l|--latitude)
    				# Tipo: float
    				[[ "$2" =~ ^-?[0-9]+\.[0-9]+$ ]] || message_error API "$_ERR_TYPE_FLOAT_" "$1" "$2"
    				latitude="$2"
    				shift 2
    				;;
    			-g|--longitude)
    				# Tipo: float
    				[[ "$2" =~ ^-?[0-9]+\.[0-9]+$ ]] || message_error API "$_ERR_TYPE_FLOAT_" "$1" "$2"
    				longitude="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    		esac
    	done
    	
    	# Parâmetros obrigatórios
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $latitude ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-l, --latitude]"
    	[[ $longitude ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-g, --longitude]"
    			
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${latitude:+-F latitude="$latitude"} \
    								 ${longitude:+-F longitude="$longitude"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Testa o retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	return $?
    	
    }
    
    # Função utlizada para enviar detalhes de um local.
    ShellBot.sendVenue()
    {
    	# Variáveis locais
    	local chat_id latitude longitude title address foursquare_id disable_notification reply_to_message_id reply_markup jq_obj
    	
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:l:g:i:a:f:n:r:k:' \
    						 --longoptions 'chat_id:,
    										latitude:,
    										longitude:,
    										title:,
    										address:,
    										foursquare_id:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-l|--latitude)
    				# Tipo: float
    				[[ "$2" =~ ^-?[0-9]+\.[0-9]+$ ]] || message_error API "$_ERR_TYPE_FLOAT_" "$1" "$2"
    				latitude="$2"
    				shift 2
    				;;
    			-g|--longitude)
    				# Tipo: float
    				[[ "$2" =~ ^-?[0-9]+\.[0-9]+$ ]] || message_error API "$_ERR_TYPE_FLOAT_" "$1" "$2"
    				longitude="$2"
    				shift 2
    				;;
    			-i|--title)
    				title="$2"
    				shift 2
    				;;
    			-a|--address)
    				address="$2"
    				shift 2
    				;;
    			-f|--foursquare_id)
    				foursquare_id="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    		esac
    	done
    			
    	# Parâmetros obrigatórios.
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $latitude ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-l, --latitude]"
    	[[ $longitude ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-g, --longitude]"
    	[[ $title ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-i, --title]"
    	[[ $address ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-a, --address]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${latitude:+-F latitude="$latitude"} \
    								 ${longitude:+-F longitude="$longitude"} \
    								 ${title:+-F title="$title"} \
    								 ${address:+-F address="$address"} \
    								 ${foursquare_id:+-F foursquare_id="$foursquare_id"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Testa o retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    }
    
    # Utilize essa função para enviar um contato + numero
    ShellBot.sendContact()
    {
    	# Variáveis locais
    	local chat_id phone_number first_name last_name disable_notification reply_to_message_id reply_markup jq_obj
    	
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:p:f:l:n:r:k:' \
    						 --longoptions 'chat_id:,
    										phone_number:,
    										first_name:,
    										last_name:,
    										disable_notification:,
    										reply_to_message_id:,
    										reply_markup:' \
    						 -- "$@")
    
    
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-p|--phone_number)
    				phone_number="$2"
    				shift 2
    				;;
    			-f|--first_name)
    				first_name="$2"
    				shift 2
    				;;
    			-l|--last_name)
    				last_name="$2"
    				shift 2
    				;;
    			-n|--disable_notification)
    				# Tipo: boolean
    				[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    				disable_notification="$2"
    				shift 2
    				;;
    			-r|--reply_to_message_id)
    				# Tipo: inteiro
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				reply_to_message_id="$2"
    				shift 2
    				;;
    			-k|--reply_markup)
    				reply_markup="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    		esac
    	done
    	
    	# Parâmetros obrigatórios.	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $phone_number ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-p, --phone_number]"
    	[[ $first_name ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-f, --first_name]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-F chat_id="$chat_id"} \
    								 ${phone_number:+-F phone_number="$phone_number"} \
    								 ${first_name:+-F first_name="$first_name"} \
    								 ${last_name:+-F last_name="$last_name"} \
    								 ${disable_notification:+-F disable_notification="$disable_notification"} \
    								 ${reply_to_message_id:+-F reply_to_message_id="$reply_to_message_id"} \
    								 ${reply_markup:+-F reply_markup="$reply_markup"})
    
    	# Testa o retorno do método
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    }
    
    # Envia uma ação para bot.
    ShellBot.sendChatAction()
    {
    	# Variáveis locais
    	local chat_id action jq_obj
    	
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:a:' \
    						 --longoptions 'chat_id:,
    										action:' \
    						 -- "$@")
    
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-a|--action)
    				[[ $2 =~ ^(typing|upload_photo|record_video|upload_video|
    							record_audio|upload_audio|upload_document|
    							find_location|record_video_note|upload_video_note)$ ]] || \
    							# erro
    							message_error API "$_ERR_ACTION_MODE_" "$1" "$2"
    				action="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    		esac
    	done
    
    	# Parâmetros obrigatórios.		
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $action ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-a, --action]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    													${action:+-d action="$action"})
    	
    	# Testa o retorno do método
    	json_status $jq_obj || message_error TG $jq_obj
    
    	# Status
    	return $?
    }
    
    # Utilize essa função para obter as fotos de um determinado usuário.
    ShellBot.getUserProfilePhotos()
    {
    	# Variáveis locais 
    	local user_id offset limit ind last index max item total jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'u:o:l:' \
    						 --longoptions 'user_id:,
    										offset:,
    										limit:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-u|--user_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				user_id="$2"
    				shift 2
    				;;
    			-o|--offset)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				offset="$2"
    				shift 2
    				;;
    			-l|--limit)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				limit="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parâmetros obrigatórios.
    	[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-u, --user_id]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${user_id:+-d user_id="$user_id"} \
    													${offset:+-d offset="$offset"} \
    													${limit:+-d limit="$limit"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
    
    		total=$(json '.result.total_count' $jq_obj)
    
    		if [[ $total -gt 0 ]]; then	
    			for index in $(seq 0 $((total-1)))
    			do
    				max=$(json ".result.photos[$index]|length" $jq_obj)
    				for item in $(seq 0 $((max-1)))
    				do
    					json ".result.photos[$index][$item]" $jq_obj | getObjVal
    				done
    			done
    		fi	
    
    	} || message_error TG $jq_obj
    	
    	# Status
    	return $?
    }
    
    # Função para listar informações do arquivo especificado.
    ShellBot.getFile()
    {
    	# Variáveis locais
    	local file_id jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'f:' \
    						 --longoptions 'file_id:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-f|--file_id)
    				file_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parâmetros obrigatórios.
    	[[ $file_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-f, --file_id]"
    	
    	# Chama o método.
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${file_id:+-d file_id="$file_id"})
    
    	# Testa o retorno do método.
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    }		
    
    # Essa função kicka o usuário do chat ou canal. (somente administradores)
    ShellBot.kickChatMember()
    {
    	# Variáveis locais
    	local chat_id user_id until_date jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:u:d:' \
    						 --longoptions 'chat_id:,
    										user_id:,
    										until_date:' \
    						 -- "$@")
    
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	# Trata os parâmetros
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-u|--user_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				user_id="$2"
    				shift 2
    				;;
    			-d|--until_date)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				until_date="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	# Parametros obrigatórios.
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-u, --user_id]"
    	
    	# Chama o método
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${user_id:+-d user_id="$user_id"} \
    								 ${until_date:+-d until_date="$until_date"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj || message_error TG $jq_obj
    
    	# Status
    	return $?
    }
    
    # Utilize essa função para remove o bot do grupo ou canal.
    ShellBot.leaveChat()
    {
    	# Variáveis locais
    	local chat_id jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:' \
    						 --longoptions 'chat_id:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj || message_error TG $jq_obj
    
    	return $?
    	
    }
    
    ShellBot.unbanChatMember()
    {
    	local chat_id user_id jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:u:' \
    						 --longoptions 'chat_id:,
    										user_id:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-u|--user_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				user_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-u, --user_id]"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${user_id:+-d user_id="$user_id"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj || message_error TG $jq_obj
    
    	return $?
    }
    
    ShellBot.getChat()
    {
    	# Variáveis locais
    	local chat_id jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:' \
    						 --longoptions 'chat_id:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    	
    	# Status
    	return $?
    }
    
    ShellBot.getChatAdministrators()
    {
    	local chat_id total key index jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:' \
    						 --longoptions 'chat_id:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
    
    		# Total de administratores
    		declare -i total=$(json '.result|length' $jq_obj)
    
    		# Lê os administradores do grupo se houver.
    		if [ $total -gt 0 ]; then
    			for index in $(seq 0 $((total-1)))
    			do
    				json ".result[$index]" $jq_obj | getObjVal
    			done
    		fi
    
    	} || message_error TG $jq_obj
    
    	# Status	
    	return $?
    }
    
    ShellBot.getChatMembersCount()
    {
    	local chat_id jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:' \
    						 --longoptions 'chat_id:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
    		json '.result' $jq_obj
    	} || message_error TG $jq_obj
    
    	return $?
    }
    
    ShellBot.getChatMember()
    {
    	# Variáveis locais
    	local chat_id user_id jq_obj
    
    	# Lê os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:u:' \
    						 --longoptions 'chat_id:,
    						 				user_id:' \
    						 -- "$@")
    
    	
    	# Define os parâmetros posicionais
    	eval set -- "$param"
    
    	while :
    	do
    		case $1 in
    			-c|--chat_id)
    				chat_id="$2"
    				shift 2
    				;;
    			-u|--user_id)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				user_id="$2"
    				shift 2
    				;;
    			--)
    				shift
    				break
    				;;
    		esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $user_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-u, --user_id]"
    	
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								${user_id:+-d user_id="$user_id"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    
    	return $?
    }
    
    ShellBot.editMessageText()
    {
    	local chat_id message_id inline_message_id text parse_mode disable_web_page_preview reply_markup jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:m:i:t:p:w:r:' \
    						 --longoptions 'chat_id:,
    										message_id:,
    										inline_message_id:,
    										text:,
    										parse_mode:,
    										disable_web_page_preview:,
    										reply_markup:' \
    						 -- "$@")
    	
    	eval set -- "$param"
    
    	while :
    	do
    			case $1 in
    				-c|--chat_id)
    					chat_id="$2"
    					shift 2
    					;;
    				-m|--message_id)
    					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    					message_id="$2"
    					shift 2
    					;;
    				-i|--inline_message_id)
    					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    					inline_message_id="$2"
    					shift 2
    					;;
    				-t|--text)
    					text="$2"
    					shift 2
    					;;
    				-p|--parse_mode)
    					[[ "$2" =~ ^(markdown|html)$ ]] || message_error API "$_ERR_TYPE_PARSE_MODE_" "$1" "$2"
    					parse_mode="$2"
    					shift 2
    					;;
    				-w|--disable_web_page_preview)
    					[[ "$2" =~ ^(true|false)$ ]] || message_error API "$_ERR_TYPE_BOOL_" "$1" "$2"
    					disable_web_page_preview="$2"
    					shift 2
    					;;
    				-r|--reply_markup)
    					reply_markup="$2"
    					shift 2
    					;;
    				--)
    					shift
    					break
    			esac
    	done
    	
    	[[ ! $chat_id && ! $message_id ]] && {
    		[[ $inline_message_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-i, --inline_message_id]"
    		unset chat_id message_id
    	} || {
    		[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    		[[ $message_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-m, --message_id]"
    		unset inline_message_id
    	} 
    	
    	[[ $text ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-t, --text]"
    
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${message_id:+-d message_id="$message_id"} \
    								 ${inline_message_id:+-d inline_message_id="$inline_message_id"} \
    								 ${text:+-d text="$text"} \
    								 ${parse_mode:+-d parse_mode="$parse_mode"} \
    								 ${disable_web_page_preview:+-d disable_web_page_preview="$disable_web_page_preview"} \
    								 ${reply_markup:+-d reply_markup="$reply_markup"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    	
    	return $?
    	
    }
    
    ShellBot.editMessageCaption()
    {
    	local chat_id message_id inline_message_id caption reply_markup jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:m:i:t:r:' \
    						 --longoptions 'chat_id:,
    										message_id:,
    										inline_message_id:,
    										caption:,
    										reply_markup:' \
    						 -- "$@")
    	
    	eval set -- "$param"
    
    	while :
    	do
    			case $1 in
    				-c|--chat_id)
    					chat_id="$2"
    					shift 2
    					;;
    				-m|--message_id)
    					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    					message_id="$2"
    					shift 2
    					;;
    				-i|--inline_message_id)
    					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    					inline_message_id="$2"
    					shift 2
    					;;
    				-t|--caption)
    					caption="$2"
    					shift 2
    					;;
    				-r|--reply_markup)
    					reply_markup="$2"
    					shift 2
    					;;
    				--)
    					shift
    					break
    			esac
    	done
    				
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $message_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-m, --message_id]"
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${message_id:+-d message_id="$message_id"} \
    								 ${inline_message_id:+-d inline_message_id="$inline_message_id"} \
    								 ${caption:+-d caption="$caption"} \
    								 ${reply_markup:+-d reply_markup="$reply_markup"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    	
    	return $?
    	
    }
    
    ShellBot.editMessageReplyMarkup()
    {
    	local chat_id message_id inline_message_id reply_markup jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:m:i:r:' \
    						 --longoptions 'chat_id:,
    										message_id:,
    										inline_message_id:,
    										reply_markup:' \
    						 -- "$@")
    	
    	eval set -- "$param"
    
    	while :
    	do
    			case $1 in
    				-c|--chat_id)
    					chat_id="$2"
    					shift 2
    					;;
    				-m|--message_id)
    					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    					message_id="$2"
    					shift 2
    					;;
    				-i|--inline_message_id)
    					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    					inline_message_id="$2"
    					shift 2
    					;;
    				-r|--reply_markup)
    					reply_markup="$2"
    					shift 2
    					;;
    				--)
    					shift
    					break
    			esac
    	done
    
    	[[ ! $chat_id && ! $message_id ]] && {
    		[[ $inline_message_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-i, --inline_message_id]"
    		unset chat_id message_id
    	} || {
    		[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    		[[ $message_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-m, --message_id]"
    		unset inline_message_id
    	} 
    	
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${message_id:+-d message_id="$message_id"} \
     								 ${inline_message_id:+-d inline_message_id="$inline_message_id"} \
    								 ${reply_markup:+-d reply_markup="$reply_markup"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
    		json '.result' $jq_obj | getObjVal
    	} || message_error TG $jq_obj
    	
    	return $?
    	
    }
    
    ShellBot.deleteMessage()
    {
    	local chat_id message_id jq_obj
    	
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'c:m:' \
    						 --longoptions 'chat_id:,
    										message_id:' \
    						 -- "$@")
    	
    	eval set -- "$param"
    
    	while :
    	do
    			case $1 in
    				-c|--chat_id)
    					chat_id="$2"
    					shift 2
    					;;
    				-m|--message_id)
    					[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    					message_id="$2"
    					shift 2
    					;;
    				--)
    					shift
    					break
    			esac
    	done
    	
    	[[ $chat_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-c, --chat_id]"
    	[[ $message_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-m, --message_id]"
    
    	jq_obj=$(curl $_CURL_OPT_ POST $_API_TELEGRAM_/${FUNCNAME#*.} ${chat_id:+-d chat_id="$chat_id"} \
    								 ${message_id:+-d message_id="$message_id"})
    
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj || message_error TG $jq_obj
    	
    	return $?
    
    }
   
	ShellBot.downloadFile() {
	
		local file_id file_info file_remote file_path filename dir opt ext
		local uri="https://api.telegram.org/file/bot$_TOKEN_"

		local param=$(getopt --name "$FUNCNAME" \
								--options 'f:d:' \
								--longoptions 'file_id:,
												dir:' \
								-- "$@")
		
		eval set -- "$param"

		while :
		do
			case $1 in
				-f|--file_id)
					opt="$1"
					file_id="$2"
					shift 2
					;;
				-d|--dir)
					[[ -d $2 ]] && {
						[[ -w $2 ]] || message_error API "$_ERR_DIR_WRITE_DENIED_" "$1" "$2"
					} || message_error API "$_ERR_DIR_NOT_FOUND_" "$1" "$2"
					dir="${2%/}"
					shift 2
					;;
				--)
					shift
					break
					;;
			esac
		done

		[[ $file_id ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-f, --file_id]"
		[[ $dir ]] || message_error API "$_ERR_PARAM_REQUIRED_" "[-d, --dir]"

		if file_info=$(ShellBot.getFile --file_id "$file_id" 2>/dev/null); then

			file_remote="$(echo $file_info | cut -d'|' -f3)"
			file_info="$(echo $file_info | cut -d'|' -f-2)"
			ext="${file_remote##*.}"
			file_path="$(mktemp -u --tmpdir="$dir" "file$(date +%d%m%Y%H%M%S)-XXXXX${ext:+.$ext}")"

			if wget "$uri/$file_remote" -O "$file_path" &>/dev/null; then
				echo "$file_info|$file_path"
			else
				message_error API "$_ERR_FILE_DOWNLOAD_" "$opt" "$file_remote"
			fi
		else
			message_error API "$_ERR_FILE_INVALID_ID_" "$opt" "$file_id"
		fi
				
		return $?
	}

    ShellBot.getUpdates()
    {
    	local total_keys offset limit timeout allowed_updates jq_obj
    
    	# Define os parâmetros da função
    	local param=$(getopt --name "$FUNCNAME" \
							 --options 'o:l:t:a:' \
    						 --longoptions 'offset:,
    										limit:,
    										timeout:,
    										allowed_updates:' \
    						 -- "$@")
    
    	
    	eval set -- "$param"
    	
    	while :
    	do
    		case $1 in
    			-o|--offset)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				offset="$2"
    				shift 2
    				;;
    			-l|--limit)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				limit="$2"
    				shift 2
    				;;
    			-t|--timeout)
    				[[ "$2" =~ ^[0-9]+$ ]] || message_error API "$_ERR_TYPE_INT_" "$1" "$2"
    				timeout="$2"
    				shift 2
    				;;
    			-a|--allowed_updates)
    				allowed_updates="$2"
    				shift 2
    				;;
    			--)
    				# Se não houver mais parâmetros
    				shift 
    				break
    				;;
    		esac
    	done
    	
    	# Seta os parâmetros
    	jq_obj=$(curl $_CURL_OPT_ GET $_API_TELEGRAM_/${FUNCNAME#*.} ${offset:+-d offset="$offset"} \
    								${limit:+-d limit="$limit"} \
    								${timeout:+-d timeout="$timeout"} \
    								${allowed_updates:+-d allowed_updates="$allowed_updates"})

		# Limpa as variáveis inicializadas.
		unset ${_var_init_list_[@]}
		unset _var_init_list_

		declare -ag _var_init_list_
		
    	# Verifica se ocorreu erros durante a chamada do método	
    	json_status $jq_obj && {
		
			# Se o modo flush estiver ativado, retorna uma coleção de objetos json contendo as atualizações.
			((_FLUSH_OFFSET_)) && { echo "$jq_obj"; return 0; }
    		
			local key key_list obj obj_cur obj_type var_name i
    
    		# Total de atualizações
    		total_keys=$(json '.result|length' $jq_obj)
    		
    		if [[ $total_keys -gt 0 ]]; then
    			
    			# Modo monitor
				((_BOT_MONITOR_)) && cat << _eof
=================== MONITOR ===================
Data: $(date '+%d/%m/%Y %T')
Script: $_BOT_SCRIPT_
Bot (nome): $(ShellBot.first_name)
Bot (usuario): $(ShellBot.username)
Bot (id): $(ShellBot.id)
_eof
    
    			# Salva e fecha o descritor de erro
    			exec 5<&2
    			exec 2<&-
    	
    			for index in $(seq 0 $((total_keys-1)))
    			do
    				# Imprime a mensagem em fila
					((_BOT_MONITOR_)) && cat << _eof
-----------------------------------------------
Mensagem: $((index + 1))
-----------------------------------------------
_eof
					# Insere o primeiro elemento da consulta.	
    				unset key_list
    				key_list[0]=".result[$index]"
    					
    				# Lê recursivamente todos os objetos.
    				while [[ ${key_list[@]} ]]
    				do
    				    i=0
    					
    				    # Lista objetos.
    					for key in ${key_list[@]}
    				    do
    						# Limpa o buffer
    				        unset key_list
    	
    						# Lê as chaves do atual objeto
    				        for obj in $(json "$key|keys[]" $jq_obj)
    				        do
    							# Se o tipo da chave for string, number ou boolean, imprime o valor armazenado.
    							# Se for object salva o nível atual em key_list. Caso contrário, lê o próximo
    							# elemento da lista.
       	         				obj_cur="$key.$obj"
    				            obj_type=$(json "$obj_cur|type" $jq_obj)

       	         			if [[ $obj_type =~ (string|number|boolean) ]]; then
    
    								# Define a nomenclatura válida para a variável que irá armazenar o valor da chave.
    	   	         				var_name=${obj_cur#.result\[$index\].}
    								var_name=${var_name//[]/}
    								var_name=${var_name//./_}
    							
    								# Cria um ponteiro para a variável armazenada em 'var_name'.
									declare -g $var_name
    								declare -n byref=$var_name
    								
    								[[ ${byref[$index]} ]] || {
    									
										# Atribui o valor de 'var_name', se a mesma não foi inicializada.
    									byref[$index]="$(json "$obj_cur" $jq_obj)"
    								
    									# Exibe a inicialização das variáveis.
										((_BOT_MONITOR_)) && sed ':a;N;s/\n/ /;ta' <<< "$var_name = '${byref[$index]}'"
    								}
									
									# Remove ponteiro
									declare +n byref
									unset byref
	
    								# Anexa a variável a lista caso não exista.
									if ! grep -qw $var_name <<< ${_var_init_list_[@]}; then
										_var_init_list_+=($var_name); fi

    							elif [[ $obj_type = object ]]; then
    				                key_list[$((i++))]=$obj_cur
    							elif [[ $obj_type = array ]]; then
    								key_list[$((i++))]=$obj_cur[]
       	         				fi
    				        done
    				    done
    				done
    			done
    		
    			# restaura o descritor de erro
    			exec 2<&5
    		fi
    	
    	} || message_error TG $jq_obj
    
    	# Status
    	return $?
    }
   
	# Bot métodos (somente leitura)
	declare -rf ShellBot.token \
				ShellBot.id \
				ShellBot.username \
				ShellBot.first_name \
				ShellBot.regHandleFunction \
				ShellBot.watchHandle \
				ShellBot.ListUpdates \
				ShellBot.TotalUpdates \
				ShellBot.OffsetEnd \
				ShellBot.OffsetNext \
				ShellBot.getMe \
				ShellBot.getWebhookInfo \
				ShellBot.deleteWebhook \
				ShellBot.setWebhook \
				ShellBot.init \
				ShellBot.ReplyKeyboardMarkup \
				ShellBot.sendMessage \
				ShellBot.forwardMessage \
				ShellBot.sendPhoto \
				ShellBot.sendAudio \
				ShellBot.sendDocument \
				ShellBot.sendSticker \
				ShellBot.sendVideo \
				ShellBot.sendVideoNote \
				ShellBot.sendVoice \
				ShellBot.sendLocation \
				ShellBot.sendVenue \
				ShellBot.sendContact \
				ShellBot.sendChatAction \
				ShellBot.getUserProfilePhotos \
				ShellBot.getFile \
				ShellBot.kickChatMember \
				ShellBot.leaveChat \
				ShellBot.unbanChatMember \
				ShellBot.getChat \
				ShellBot.getChatAdministrators \
				ShellBot.getChatMembersCount \
				ShellBot.getChatMember \
				ShellBot.editMessageText \
				ShellBot.editMessageCaption \
				ShellBot.editMessageReplyMarkup \
				ShellBot.InlineKeyboardMarkup \
				ShellBot.InlineKeyboardButton \
				ShellBot.answerCallbackQuery \
				ShellBot.deleteMessage \
				ShellBot.exportChatInviteLink \
				ShellBot.setChatPhoto \
				ShellBot.deleteChatPhoto \
				ShellBot.setChatTitle \
				ShellBot.setChatDescription \
				ShellBot.pinChatMessage \
				ShellBot.unpinChatMessage \
				ShellBot.promoteChatMember \
				ShellBot.restrictChatMember \
				ShellBot.getStickerSet \
				ShellBot.uploadStickerFile \
				ShellBot.createNewStickerSet \
				ShellBot.addStickerToSet \
				ShellBot.setStickerPositionInSet \
				ShellBot.deleteStickerFromSet \
				ShellBot.stickerMaskPosition \
				ShellBot.downloadFile \
				ShellBot.getUpdates
   
	# Retorna objetos
	echo "$(ShellBot.id)|$(ShellBot.username)|$(ShellBot.first_name)|$(((_FLUSH_OFFSET_)) && flushOffset)"

	# status
   	return 0
}

# Funções (somente leitura)
declare -rf message_error \
            json \
            json_status \
            getObjVal \
			flushOffset \
			createUnitService
