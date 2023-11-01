create procedure syn.usp_ImportFileCustomerSeasonal
	@ID_Record int
-- 1.Операторы и системные функции пишутся в нижнем регистре
as
set nocount on
begin
	declare 
		-- 2.Все переменные задаются в одном объявлении
		@RowCount int = (select count(*) from syn.SA_CustomerSeasonal)
		,@ErrorMessage varchar(max)
	-- 3.Отступ комментария должен совпадать с отступом кода ниже
	-- Проверка на корректность загрузки
	if not exists (
		-- 4.Не сделан отступ
		select 1
		-- 5.Некорректное присваивание имени alias объекту
		from syn.ImportFile as f 
		where f.ID = @ID_Record
			 -- Не сделан отступ
			and f.FlagLoaded = cast(1 as bit)
	)
	-- 6.Операторы if и else с begin/end должны быть на одном уровне
	begin
		set @ErrorMessage = 'Ошибка при загрузке файла, проверьте корректность данных'

		raiserror(@ErrorMessage, 3, 1)
			
		-- 7.Перед return пустая строка
		return
	end
	-- 8.Между -- и текстом комментария должен быть пробел
	-- Чтение из слоя временных данных
	select
		c.ID as ID_dbo_Customer
		,cst.ID as ID_CustomerSystemType
		,s.ID as ID_Season
		,cast(cs.DateBegin as date) as DateBegin
		,cast(cs.DateEnd as date) as DateEnd
		,c_dist.ID as ID_dbo_CustomerDistributor
		,cast(isnull(cs.FlagActive, 0) as bit) as FlagActive
	into #CustomerSeasonal
	-- 9.Указываем alias явно с помощью ключевого слова as
	from syn.SA_CustomerSeasonal as cs
		-- 10.Указываем вид join явно
		inner join dbo.Customer as c on c.UID_DS = cs.UID_DS_Customer
			and c.ID_mapping_DataSource = 1
		inner join dbo.Season as s on s.Name = cs.Season
		inner join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor
			and cd.ID_mapping_DataSource = 1
		-- 11.При соединение двух таблиц, сперва после on указываем поле присоединяемой таблицы
		inner join syn.CustomerSystemType as cst on cst.Name = cs.CustomerSystemType
	where try_cast(cs.DateBegin as date) is not null
		and try_cast(cs.DateEnd as date) is not null
		and try_cast(isnull(cs.FlagActive, 0) as bit) is not null
	-- 12.Добавляем пустую строку

	-- Определяем некорректные записи
	-- Добавляем причину, по которой запись считается некорректной

	select
		cs.*
		,case
			-- 13.Переносим then на новую строку с дополнительным отступом
			when c.ID is null 
				then 'UID клиента отсутствует в справочнике "Клиент"'
			when c_dist.ID is null 
				then 'UID дистрибьютора отсутствует в справочнике "Клиент"'
			when s.ID is null 
				then 'Сезон отсутствует в справочнике "Сезон"'
			when cst.ID is null 
				then 'Тип клиента отсутствует в справочнике "Тип клиента"'
			when try_cast(cs.DateBegin as date) is null 
				then 'Невозможно определить Дату начала'
			when try_cast(cs.DateEnd as date) is null 
				then 'Невозможно определить Дату окончания'
			when try_cast(isnull(cs.FlagActive, 0) as bit) is null 
				then 'Невозможно определить Активность'
		end as Reason
	into #BadInsertedRows
	from syn.SA_CustomerSeasonal as cs
		-- 14.Делаем join c отступом
		left join dbo.Customer as c on c.UID_DS = cs.UID_DS_Customer
			and c.ID_mapping_DataSource = 1
		left join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor 
			-- 15.Для большей читаемости применяем перенос строки
			and c_dist.ID_mapping_DataSource = 1
		left join dbo.Season as s on s.Name = cs.Season
		left join syn.CustomerSystemType as cst on cst.Name = cs.CustomerSystemType
	where cc.ID is null
		or cd.ID is null
		or s.ID is null
		or cst.ID is null
		or try_cast(cs.DateBegin as date) is null
		or try_cast(cs.DateEnd as date) is null
		or try_cast(isnull(cs.FlagActive, 0) as bit) is null

	-- Обработка данных из файла
	merge into syn.CustomerSeasonal as cs
	using (
		select
			cs_temp.ID_dbo_Customer
			,cs_temp.ID_CustomerSystemType
			,cs_temp.ID_Season
			,cs_temp.DateBegin
			,cs_temp.DateEnd
			,cs_temp.ID_dbo_CustomerDistributor
			,cs_temp.FlagActive
		from #CustomerSeasonal as cs_temp
	) as s on s.ID_dbo_Customer = cs.ID_dbo_Customer
		and s.ID_Season = cs.ID_Season
		and s.DateBegin = cs.DateBegin
	when matched 
		and t.ID_CustomerSystemType <> s.ID_CustomerSystemType then
		update
		set
			ID_CustomerSystemType = s.ID_CustomerSystemType
			,DateEnd = s.DateEnd
			,ID_dbo_CustomerDistributor = s.ID_dbo_CustomerDistributor
			,FlagActive = s.FlagActive
	when not matched then
		-- 16.Для большей читаемости применяем перенос строки
		insert (ID_dbo_Customer, ID_CustomerSystemType, ID_Season, DateBegin, DateEnd, 
		ID_dbo_CustomerDistributor, FlagActive)
		values (s.ID_dbo_Customer, s.ID_CustomerSystemType, s.ID_Season, s.DateBegin, s.DateEnd,
		-- 17.Нет смысла в переносе ; на следующую строку
		s.ID_dbo_CustomerDistributor, s.FlagActive);

	-- Информационное сообщение
	begin
		select @ErrorMessage = concat('Обработано строк: ', @RowCount)

		raiserror(@ErrorMessage, 1, 1)

		-- Формирование таблицы для отчетности
		select top 100
			Season as 'Сезон'
			,UID_DS_Customer as 'UID Клиента'
			,Customer as 'Клиент'
			,CustomerSystemType as 'Тип клиента'
			,UID_DS_CustomerDistributor as 'UID Дистрибьютора'
			,CustomerDistributor as 'Дистрибьютор'
			,isnull(format(try_cast(DateBegin as date), 'dd.MM.yyyy', 'ru-RU'), DateBegin) as 'Дата начала'
			,isnull(format(try_cast(DateEnd as date), 'dd.MM.yyyy', 'ru-RU'), DateEnd) as 'Дата окончания'
			,FlagActive as 'Активность'
			,Reason as 'Причина'
		from #BadInsertedRows

		return
	end

end
