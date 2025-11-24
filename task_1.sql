-- DDL

Create Schema test;

/* 
Перед тем, как строить структуру нормализованной БД и назначать типы данных для столбцов,
я быстро исследовал данные с помощью pandas (файл task_1.ipynb), посмотрел на их вид и их особенности,
также с помощью python пришлось немного подшаманить исходный csv-файл, так как каждая строка там была обрамлена в ковычки,
из-за чего с помощью sql не получается адекватно его прочитать (исправленный файл - auto_fixed.csv).
Также в ходе исследования я заметил, что для всех автомобилей Porsche по какой-то причине не указана страна (хотя должна быть Германия), 
в задании про исправление или дополнение самих данных ничего не сказано, поэтому я решил их не трогать.
*/


/* 
В этой таблице большинство типов данных для колонок совпадают с теми, что будут
назначены колонкам в нормализованных таблицах (за исключением auto, которая будет разбита на несколько колонок в разных таблицах),
поэтому почти все пояснения к выбору типов будут здесь.
*/
CREATE TABLE test.auto_sales
(
	id INT PRIMARY KEY,
	auto VARCHAR(50) NOT NULL, -- макс длина поля в данных - 23 символа, 50 - большой запас
	gasoline_consumption DECIMAL(3, 1), -- в данных у всех значений до 1 знака после запятой и макс значение 12
	price DECIMAL(11, 4) NOT NULL, -- макс значение не превышает 100 000, здесь запас до 9 999 999, 
	date DATE NOT NULL, -- даты указаны лишь в формате YYYY-MM-DD
	person_name VARCHAR(50) NOT NULL, -- макс длина поля в данных - 26 символа, 50 - большой запас
	phone VARCHAR(30) NOT NULL, -- номера указаны в большом числе различных форматов с макс длиной строки - 22 символа
	discount INT NOT NULL, -- скидка в данных везде имеет целое значение от 0 до 20
	brand_origin VARCHAR(20) -- макс длина в данных - 11 символов (South Korea)
);

-- Нормализованная структура

-- 1. Таблица стран
CREATE TABLE test.countries (
	country_id SERIAL PRIMARY KEY,
	country_name VARCHAR(20) NOT NULL UNIQUE
);

-- 2. Таблица производителей
/*
Для всех записей в данных в поле auto первое слово - имя компании-производителя, 
уникальных знечений всего 7 штук, поэтому я выделил их в отдельную таблицу.
Также для всех автомобилей каждого бренда указана только одна страна, поэтому
я привязал производителя к стране.
*/
CREATE TABLE test.brands (
	brand_id SERIAL PRIMARY KEY,
	brand_name VARCHAR(20) NOT NULL UNIQUE,
	country_id INT REFERENCES test.countries(country_id)
);

-- 3. Таблица цветов
/* 
В данных в таблице auto во всех строках после символа запятой указан цвет,
уникальных значений которого всего 8 штук, поэтому для избежания дублирования
данных я выделил цвета в отдельную таблицу.
*/
CREATE TABLE test.colors (
	color_id SERIAL PRIMARY KEY,
	color_name VARCHAR(20) NOT NULL UNIQUE 
);

-- 4. Таблица моделей автомобилей
CREATE TABLE test.car_models (
	model_id SERIAL PRIMARY KEY,
	model_name VARCHAR(30) NOT NULL, -- здесь будет храниться только подсторка исходного поля auto исключая название производителя и цвет 
	brand_id INT REFERENCES test.brands(brand_id),
	gasoline_consumption DECIMAL(3,1),
	UNIQUE(model_name, brand_id)
);

-- 5. Таблица покупателей
CREATE TABLE test.customers (
	customer_id SERIAL PRIMARY KEY,
	person_name VARCHAR(50) NOT NULL, -- person_name не разделил на фамилию и имя, т.к. там также иногда 
									  -- указываются приставки (Mrs., Miss и др.) или другие слова
	phone VARCHAR(30) NOT NULL UNIQUE
);

-- 6. Таблица продаж
CREATE TABLE test.sales (
	sale_id SERIAL PRIMARY KEY,
	model_id INT REFERENCES test.car_models(model_id),
	color_id INT REFERENCES test.colors(color_id),
	customer_id INT REFERENCES test.customers(customer_id),
	price DECIMAL(11,4) NOT NULL,
	sale_date DATE NOT NULL,
	discount INT NOT NULL CHECK (discount BETWEEN 0 AND 100) -- в предоставленном наборе данных скидка колеблется от 0 до 20,
);															 -- проверку от 0 до 100 добавил лишь для потенциального добавления новых данных


-- Импорт данных

COPY test.auto_sales FROM 'D:\Projects\Jupyter\agsr_test\auto_fixed.csv' 
WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"', NULL 'null');

SELECT * FROM test.auto_sales;



--	Трансформация данных и наполнение нормализованных таблиц									     


-- 1. Страны
INSERT INTO test.countries (country_name)
SELECT DISTINCT brand_origin 
FROM test.auto_sales 
WHERE brand_origin IS NOT NULL;

-- 2. Производители
INSERT INTO test.brands (brand_name, country_id)
SELECT DISTINCT 
	SPLIT_PART(auto, ' ', 1) as brand_name,
	c.country_id
FROM test.auto_sales a
LEFT JOIN test.countries c ON a.brand_origin = c.country_name;

-- 3. Цвета
INSERT INTO test.colors (color_name)
SELECT DISTINCT 
	TRIM(SPLIT_PART(auto, ',', 2)) as color_name
FROM test.auto_sales;

-- 4. Модели автомобилей
INSERT INTO test.car_models (model_name, brand_id, gasoline_consumption)
SELECT DISTINCT
	TRIM(SUBSTRING(SPLIT_PART(auto, ',', 1) FROM POSITION(' ' IN SPLIT_PART(auto, ',', 1)) + 1)) as model_name,
	b.brand_id,
	a.gasoline_consumption
FROM test.auto_sales a
JOIN test.brands b ON SPLIT_PART(a.auto, ' ', 1) = b.brand_name
ON CONFLICT (model_name, brand_id) DO NOTHING;

-- 5. Покупатели
INSERT INTO test.customers (person_name, phone)
SELECT DISTINCT 
	person_name,
	phone
FROM test.auto_sales;

-- 6. Продажи
INSERT INTO test.sales (sale_id, model_id, color_id, customer_id, price, sale_date, discount)
SELECT 
	a.id,
	cm.model_id,
	col.color_id,
	c.customer_id,
	a.price,
	a.date,
	a.discount
FROM test.auto_sales a
JOIN test.brands b ON SPLIT_PART(a.auto, ' ', 1) = b.brand_name
JOIN test.car_models cm ON 
	cm.brand_id = b.brand_id AND 
	cm.model_name = TRIM(SUBSTRING(SPLIT_PART(a.auto, ',', 1) FROM POSITION(' ' IN SPLIT_PART(a.auto, ',', 1)) + 1))
JOIN test.colors col ON TRIM(SPLIT_PART(a.auto, ',', 2)) = col.color_name
JOIN test.customers c ON a.person_name = c.person_name AND a.phone = c.phone;


-- Аналитические запросы


-- 1. Рассчитайте процент автомобильных моделей, для которых не указан расход бензина.

SELECT (SELECT COUNT(*)::FLOAT AS null_count 
FROM test.car_models
WHERE gasoline_consumption IS NULL) / COUNT(*) * 100
FROM test.car_models;

-- 2. Для каждого бренда выведите среднюю цену автомобилей по годам с учетом скидки. Отсортируйте по бренду и году по возрастанию.

SELECT 
	brand_name, 
	EXTRACT(year FROM sale_date) as year, 
	AVG(price * (100 - discount)/100) as avg_price
FROM test.sales s
JOIN test.car_models cm ON s.model_id = cm.model_id
JOIN test.brands b ON cm.brand_id = b.brand_id
GROUP BY brand_name, year
ORDER BY brand_name, year;

-- 3. Выведите среднюю цену автомобилей по месяцам за 2021 год с учетом скидки. Отсортируйте по месяцам по возрастанию.

SELECT 
	EXTRACT(month FROM sale_date) as month, 
	AVG(price * (100 - discount)/100) as avg_price
FROM test.sales
WHERE EXTRACT(year FROM sale_date) = 2021
GROUP BY month
ORDER BY month;

-- 4. Для каждого пользователя выведите через запятую список купленных им автомобилей (в формате "Бренд Модель"). Сортировка машин в строке не требуется.

SELECT 
	c.customer_id,
	person_name,
	STRING_AGG(brand_name || ' ' || model_name, ', ') as auto
FROM test.sales s
JOIN test.customers c ON s.customer_id = c.customer_id
JOIN test.car_models cm ON s.model_id = cm.model_id
JOIN test.brands b ON cm.brand_id = b.brand_id
GROUP BY c.customer_id, person_name;

-- 5. Определите максимальную и минимальную цену автомобилей по странам-производителям без учета скидки.

SELECT
	country_name,
	MAX(price) as max_price,
	MIN(price) as min_price
FROM test.countries cn
JOIN test.brands b ON cn.country_id = b.country_id
JOIN test.car_models cm ON b.brand_id = cm.brand_id
JOIN test.sales s ON cm.model_id = s.model_id
GROUP BY country_name;

/* 
На самом деле максимальная цена в предоставленном наборе данных составляет 92512.095,
но она пренадлежит автомобилю Porsche, для которых здесь страна по какой-то причине не определена
(хотя фактически должна быть Германия). Поэтому для Германии здесь максимальная цена занижена.
/*